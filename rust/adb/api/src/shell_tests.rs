//! 快速退出的真实回执不能被关闭 stdin 的竞态覆盖；缺失退出回执仍失败。
use super::*;
use interop_adb::{
    DeviceInfo,
    protocol::{self, Frame},
};

#[tokio::test]
async fn fast_shell_exit_survives_rejected_stdin_close_without_inventing_an_exit() {
    for exit in [true, false] {
        let (transport, mut peer) = tokio::io::duplex(4096);
        let client = Client::from_negotiated_transport(
            transport,
            DeviceInfo {
                version: protocol::VERSION,
                max_payload: 4096,
                banner: "device::".into(),
                features: ["shell_v2".to_owned()].into_iter().collect(),
            },
        )
        .unwrap();
        let connection = insert_connection(client.clone(), "fast-shell".into(), false)
            .unwrap()
            .id;
        let serving = tokio::spawn(async move {
            let open = Frame::read(&mut peer, 4096, true).await.unwrap();
            assert_eq!(open.payload, b"shell,v2,raw:printf done\0");
            Frame::new(protocol::OKAY, 7, open.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            let mut output = b"\x01\x04\0\0\0done".to_vec();
            if exit {
                output.extend_from_slice(b"\x03\x01\0\0\0\0");
            }
            Frame::new(protocol::WRTE, 7, open.arg0, output)
                .write(&mut peer)
                .await
                .unwrap();
            // 先关闭远端流，不确认随后到达的 closeStdin WRTE；连接本身保持存活。
            Frame::new(protocol::CLSE, 7, open.arg0, [])
                .write(&mut peer)
                .await
                .unwrap();
            while Frame::read(&mut peer, 4096, true).await.is_ok() {}
        });
        let id = adb_shell(connection.clone(), "printf done".into(), 2000)
            .await
            .unwrap();
        let output = adb_service_next(id.clone()).await.unwrap().unwrap();
        assert_eq!(output.bytes, b"done");
        assert!(!output.done);
        let terminal = adb_service_next(id.clone()).await;
        if exit {
            let terminal = terminal.unwrap().unwrap();
            assert!(terminal.done);
            assert_eq!(terminal.exit_code, Some(0));
        } else {
            assert!(terminal.is_err(), "没有真实 Exit 不能确认命令完成");
        }
        assert!(!client.is_closed());
        adb_cancel(id).await.unwrap();
        adb_disconnect(connection).await.unwrap();
        client.close();
        serving.await.unwrap();
    }
}
