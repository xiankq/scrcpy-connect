use super::*;

#[test]
fn desktop_usb_selection_requires_an_explicit_attached_device_when_multiple_are_present() {
    let devices = vec!["first-attachment".into(), "second-attachment".into()];
    assert_eq!(select_usb_device(&devices, None).unwrap(), None);
    assert_eq!(
        select_usb_device(&devices, Some("second-attachment")).unwrap(),
        Some(1)
    );
    // A reordered enumeration must keep selecting the requested physical attachment.
    let reversed = devices.into_iter().rev().collect::<Vec<_>>();
    assert_eq!(
        select_usb_device(&reversed, Some("second-attachment")).unwrap(),
        Some(0)
    );
}

#[test]
fn desktop_usb_selection_never_substitutes_another_device_after_detach() {
    let devices = vec!["another-attachment".into()];
    assert_eq!(
        select_usb_device(&devices, Some("removed-attachment"))
            .unwrap_err()
            .code,
        "usb_removed"
    );
    assert_eq!(
        select_usb_device(&[], Some("removed-attachment"))
            .unwrap_err()
            .code,
        "usb_removed"
    );
    assert_eq!(
        select_usb_device(&[], None).unwrap_err().code,
        "usb_not_found"
    );
    assert_eq!(select_usb_device(&devices, None).unwrap(), Some(0));
}
