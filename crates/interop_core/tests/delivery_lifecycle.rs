use interop_core::Runtime;
use serde_json::{Value, json};

fn source() -> Value {
    json!({"sourceId":"transfer-1","localPath":"/private/cache/report.txt","kind":"file"})
}

fn begin(operation: &str) -> Value {
    let mut params = source();
    params["operationId"] = json!(operation);
    params["name"] = json!("report.txt");
    params
}

fn finish(operation: &str, result: Value) -> Value {
    let mut params = source();
    params["operationId"] = json!(operation);
    params["result"] = result;
    params
}

#[tokio::test]
async fn pending_delivery_survives_reopen_as_unknown_without_replay() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    assert!(runtime.invoke("delivery.get", source()).await.unwrap()["record"].is_null());
    let receipt = runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    assert_eq!(receipt["record"]["status"], "pending");
    drop(runtime);
    let reopened = Runtime::initialize(directory.path()).await.unwrap();
    let receipt = reopened.invoke("delivery.get", source()).await.unwrap();
    assert_eq!(receipt["record"]["operationId"], "export-1");
    assert_eq!(receipt["record"]["status"], "result_unknown");
    assert_eq!(receipt["record"]["result"]["status"], "result_unknown");
    drop(reopened);
    let reopened = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        reopened.invoke("delivery.get", source()).await.unwrap()["record"],
        receipt["record"]
    );
}

#[tokio::test]
async fn unknown_requires_review_of_exact_operation_before_a_fresh_save() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    drop(runtime);
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-2"))
            .await
            .unwrap_err()
            .code,
        "delivery_review_required"
    );
    let mut params = begin("export-2");
    params["reviewedOperationId"] = json!("wrong-operation");
    assert_eq!(
        runtime
            .invoke("delivery.begin", params.clone())
            .await
            .unwrap_err()
            .code,
        "delivery_review_required"
    );
    params["reviewedOperationId"] = json!("export-1");
    let record = runtime.invoke("delivery.begin", params).await.unwrap();
    assert_eq!(record["record"]["status"], "pending");
    assert_eq!(record["record"]["operationId"], "export-2");
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-3"))
            .await
            .unwrap_err()
            .code,
        "delivery_busy"
    );
}

#[tokio::test]
async fn saved_result_is_durable_and_old_or_conflicting_receipts_cannot_replace_it() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    let params = finish(
        "export-1",
        json!({"status":"saved","name":"actual.txt","files":1,"bytes":24,"uri":"content://secret","created":[{"handle":"secret"}]}),
    );
    let saved = runtime
        .invoke("delivery.finish", params.clone())
        .await
        .unwrap();
    assert_eq!(saved["record"]["status"], "saved");
    assert_eq!(saved["record"]["result"]["bytes"], 24);
    assert!(saved["record"]["result"].get("uri").is_none());
    assert!(saved["record"]["result"].get("created").is_none());
    assert_eq!(
        runtime.invoke("delivery.finish", params).await.unwrap(),
        saved
    );
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-old", json!({"status":"failed"}))
            )
            .await
            .unwrap_err()
            .code,
        "delivery_operation_mismatch"
    );
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-1", json!({"status":"failed"}))
            )
            .await
            .unwrap_err()
            .code,
        "delivery_result_conflict"
    );
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-2"))
            .await
            .unwrap_err()
            .code,
        "delivery_saved"
    );
    drop(runtime);
    let reopened = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        reopened.invoke("delivery.get", source()).await.unwrap(),
        saved
    );
}

#[tokio::test]
async fn saved_content_requires_exact_explicit_additional_copy_authorization() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    runtime
        .invoke(
            "delivery.finish",
            finish("export-1", json!({"status":"saved"})),
        )
        .await
        .unwrap();
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-2"))
            .await
            .unwrap_err()
            .code,
        "delivery_saved"
    );
    let mut copy = begin("export-2");
    copy["additionalCopyOfOperationId"] = json!("older-saved-operation");
    assert_eq!(
        runtime
            .invoke("delivery.begin", copy.clone())
            .await
            .unwrap_err()
            .code,
        "delivery_saved"
    );
    copy["additionalCopyOfOperationId"] = json!("export-1");
    let receipt = runtime.invoke("delivery.begin", copy).await.unwrap();
    assert_eq!(receipt["record"]["operationId"], "export-2");
    assert_eq!(receipt["record"]["status"], "pending");
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-1", json!({"status":"saved"}))
            )
            .await
            .unwrap_err()
            .code,
        "delivery_operation_mismatch"
    );
    runtime
        .invoke(
            "delivery.finish",
            finish("export-2", json!({"status":"result_unknown"})),
        )
        .await
        .unwrap();
    let mut unknown = begin("export-3");
    unknown["additionalCopyOfOperationId"] = json!("export-2");
    assert_eq!(
        runtime
            .invoke("delivery.begin", unknown)
            .await
            .unwrap_err()
            .code,
        "delivery_review_required"
    );
}

#[tokio::test]
async fn partial_destination_requires_review_but_safe_failure_and_picker_cancel_allow_new_operation()
 {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    let partial = runtime.invoke("delivery.finish", finish("export-1", json!({"status":"partial","partialDestinationPossible":true,"files":2,"errors":[{"path":"a/b","code":"write_failed","message":"Full","handle":"secret"}]}))).await.unwrap();
    assert_eq!(partial["record"]["status"], "partial");
    assert_eq!(
        partial["record"]["result"]["errors"],
        json!([{"path":"a/b","code":"write_failed","message":"Full"}])
    );
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-2"))
            .await
            .unwrap_err()
            .code,
        "delivery_review_required"
    );
    let mut reviewed = begin("export-2");
    reviewed["reviewedOperationId"] = json!("export-1");
    runtime.invoke("delivery.begin", reviewed).await.unwrap();
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-1", json!({"status":"saved"}))
            )
            .await
            .unwrap_err()
            .code,
        "delivery_operation_mismatch"
    );
    runtime
        .invoke(
            "delivery.finish",
            finish(
                "export-2",
                json!({"status":"cancelled","partialDestinationPossible":false}),
            ),
        )
        .await
        .unwrap();
    runtime
        .invoke("delivery.begin", begin("export-3"))
        .await
        .unwrap();
    runtime
        .invoke(
            "delivery.finish",
            finish(
                "export-3",
                json!({"status":"failed","partialDestinationPossible":false}),
            ),
        )
        .await
        .unwrap();
    runtime
        .invoke("delivery.begin", begin("export-4"))
        .await
        .unwrap();
    let unknown = runtime
        .invoke(
            "delivery.finish",
            finish(
                "export-4",
                json!({"status":"resultUnknown","partialDestinationPossible":false}),
            ),
        )
        .await
        .unwrap();
    assert_eq!(unknown["record"]["status"], "result_unknown");
    assert_eq!(
        unknown["record"]["result"]["partialDestinationPossible"],
        true
    );
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish(
                    "export-4",
                    json!({"status":"failed","partialDestinationPossible":false})
                )
            )
            .await
            .unwrap_err()
            .code,
        "delivery_result_conflict"
    );
}

#[tokio::test]
async fn replacing_an_operation_never_makes_older_operation_ids_valid_again() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for operation in ["export-1", "export-2"] {
        runtime
            .invoke("delivery.begin", begin(operation))
            .await
            .unwrap();
        runtime
            .invoke(
                "delivery.finish",
                finish(
                    operation,
                    json!({"status":"cancelled","partialDestinationPossible":false}),
                ),
            )
            .await
            .unwrap();
    }
    drop(runtime);
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-1"))
            .await
            .unwrap_err()
            .code,
        "delivery_operation_reused"
    );
    assert_eq!(
        runtime.invoke("delivery.get", source()).await.unwrap()["record"]["operationId"],
        "export-2"
    );
}

#[tokio::test]
async fn simultaneous_begins_admit_one_and_sources_are_exact_tuples() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let (first, second) = tokio::join!(
        runtime.invoke("delivery.begin", begin("export-1")),
        runtime.invoke("delivery.begin", begin("export-2")),
    );
    assert_ne!(first.is_ok(), second.is_ok());
    assert_eq!(first.err().or(second.err()).unwrap().code, "delivery_busy");
    let mut alternate = begin("export-3");
    alternate["sourceId"] = json!("other-device");
    runtime
        .invoke("delivery.begin", alternate.clone())
        .await
        .unwrap();
    alternate["operationId"] = json!("export-4");
    alternate["kind"] = json!("directory");
    runtime
        .invoke("delivery.begin", alternate.clone())
        .await
        .unwrap();
    assert_eq!(
        runtime.invoke("delivery.get", alternate).await.unwrap()["record"]["operationId"],
        "export-4"
    );
    let mut missing = finish("export-3", json!({"status":"saved"}));
    missing["localPath"] = json!("/different/path");
    assert_eq!(
        runtime
            .invoke("delivery.finish", missing)
            .await
            .unwrap_err()
            .code,
        "delivery_not_found"
    );
    assert_eq!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-3", json!({"status":"saved"}))
            )
            .await
            .unwrap_err()
            .code,
        "delivery_operation_mismatch"
    );
}

#[tokio::test]
async fn unconfirmed_failure_cannot_authorize_retry_and_empty_early_failure_name_is_valid() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    let result = runtime
        .invoke(
            "delivery.finish",
            finish("export-1", json!({"status":"failed","name":""})),
        )
        .await
        .unwrap();
    assert_eq!(
        result["record"]["result"]["partialDestinationPossible"],
        true
    );
    assert_eq!(
        runtime
            .invoke("delivery.begin", begin("export-2"))
            .await
            .unwrap_err()
            .code,
        "delivery_review_required"
    );
}

#[tokio::test]
async fn invalid_parameters_leave_admitted_operation_pending() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    for field in ["sourceId", "localPath", "kind", "operationId", "name"] {
        let mut params = begin("export-1");
        params[field] = json!("");
        assert_eq!(
            runtime
                .invoke("delivery.begin", params)
                .await
                .unwrap_err()
                .code,
            "invalid_argument"
        );
    }
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    for result in [
        json!(null),
        json!({"status":"imported"}),
        json!({"status":"saved","files":-1}),
        json!({"status":"saved","bytes":1.5}),
        json!({"status":"failed","partialDestinationPossible":"false"}),
        json!({"status":"failed","errors":["bad"]}),
    ] {
        assert_eq!(
            runtime
                .invoke("delivery.finish", finish("export-1", result))
                .await
                .unwrap_err()
                .code,
            "invalid_argument"
        );
        assert_eq!(
            runtime.invoke("delivery.get", source()).await.unwrap()["record"]["status"],
            "pending"
        );
    }
}

#[tokio::test]
async fn failed_persistence_never_publishes_begin_or_finish_in_memory() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let journal = directory.path().join("deliveries.json");
    std::fs::create_dir(&journal).unwrap();
    assert!(
        runtime
            .invoke("delivery.begin", begin("export-1"))
            .await
            .is_err()
    );
    assert!(runtime.invoke("delivery.get", source()).await.unwrap()["record"].is_null());
    std::fs::remove_dir(&journal).unwrap();
    runtime
        .invoke("delivery.begin", begin("export-1"))
        .await
        .unwrap();
    std::fs::remove_file(&journal).unwrap();
    std::fs::create_dir(&journal).unwrap();
    assert!(
        runtime
            .invoke(
                "delivery.finish",
                finish("export-1", json!({"status":"saved"}))
            )
            .await
            .is_err()
    );
    assert_eq!(
        runtime.invoke("delivery.get", source()).await.unwrap()["record"]["status"],
        "pending"
    );
    std::fs::remove_dir(&journal).unwrap();
    runtime
        .invoke(
            "delivery.finish",
            finish("export-1", json!({"status":"saved"})),
        )
        .await
        .unwrap();
    drop(runtime);
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        runtime.invoke("delivery.get", source()).await.unwrap()["record"]["status"],
        "saved"
    );
}

#[tokio::test]
async fn full_journal_refuses_new_exports_and_retains_saved_and_unknown_records() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    runtime
        .invoke("delivery.begin", begin("saved-1"))
        .await
        .unwrap();
    runtime
        .invoke(
            "delivery.finish",
            finish("saved-1", json!({"status":"saved"})),
        )
        .await
        .unwrap();
    for index in 1..1024 {
        let mut params = begin(&format!("export-{index}"));
        params["sourceId"] = json!(format!("source-{index}"));
        runtime.invoke("delivery.begin", params).await.unwrap();
    }
    let mut extra = begin("overflow");
    extra["sourceId"] = json!("overflow-source");
    assert_eq!(
        runtime
            .invoke("delivery.begin", extra)
            .await
            .unwrap_err()
            .code,
        "delivery_capacity"
    );
    drop(runtime);
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    assert_eq!(
        runtime.invoke("delivery.get", source()).await.unwrap()["record"]["status"],
        "saved"
    );
    let mut unknown = source();
    unknown["sourceId"] = json!("source-1");
    assert_eq!(
        runtime.invoke("delivery.get", unknown).await.unwrap()["record"]["status"],
        "result_unknown"
    );
}

#[tokio::test]
async fn malformed_or_oversized_journal_fails_closed_instead_of_forgetting_saves() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    drop(runtime);
    for bytes in [
        b"{".to_vec(),
        br#"{"version":99,"records":{},"operations":[]}"#.to_vec(),
        br#"{"version":1,"records":{"wrong-key":{"operationId":"export-1","sourceId":"transfer-1","localPath":"/private/cache/report.txt","kind":"file","name":"report.txt","status":"saved","result":null,"updatedAt":0}},"operations":["export-1"]}"#.to_vec(),
        vec![b' '; 4 * 1024 * 1024 + 1],
    ] {
        std::fs::write(directory.path().join("deliveries.json"), bytes).unwrap();
        let error = Runtime::initialize(directory.path()).await.err().unwrap();
        assert_eq!(error.code, "delivery_storage_invalid");
    }
}

#[tokio::test]
async fn bounded_error_summaries_cannot_exceed_journal_bytes_or_erase_pending_admission() {
    let directory = tempfile::tempdir().unwrap();
    let runtime = Runtime::initialize(directory.path()).await.unwrap();
    let long = "界".repeat(2000);
    let errors = vec![
        json!({"path":long,"message":long,"code":"write_failed","uri":"content://secret"});
        150
    ];
    let mut reached_capacity = false;
    for index in 0..10 {
        let operation = format!("export-{index}");
        let mut params = begin(&operation);
        params["sourceId"] = json!(format!("source-{index}"));
        runtime
            .invoke("delivery.begin", params.clone())
            .await
            .unwrap();
        params["result"] =
            json!({"status":"partial","partialDestinationPossible":true,"errors":errors});
        match runtime.invoke("delivery.finish", params.clone()).await {
            Ok(receipt) => {
                let retained = receipt["record"]["result"]["errors"].as_array().unwrap();
                assert_eq!(retained.len(), 100);
                assert!(retained[0]["message"].as_str().unwrap().len() <= 4096);
                assert!(retained[0]["path"].as_str().unwrap().len() <= 4096);
                assert!(retained[0].get("uri").is_none());
            }
            Err(error) => {
                assert_eq!(error.code, "delivery_capacity");
                assert_eq!(
                    runtime
                        .invoke("delivery.get", params.clone())
                        .await
                        .unwrap()["record"]["status"],
                    "pending"
                );
                params["result"] = json!({"status":"result_unknown"});
                runtime
                    .invoke("delivery.finish", params.clone())
                    .await
                    .unwrap();
                drop(runtime);
                let reopened = Runtime::initialize(directory.path()).await.unwrap();
                assert_eq!(
                    reopened.invoke("delivery.get", params).await.unwrap()["record"]["status"],
                    "result_unknown"
                );
                reached_capacity = true;
                break;
            }
        }
    }
    assert!(reached_capacity);
}
