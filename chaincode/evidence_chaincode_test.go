package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-chaincode-go/shimtest"
)

const (
	testBatchID       = "bch_v1_tomcat-cve-2017-12615_20260422T020500Z"
	testMerkleRoot    = "36adaf679ffc6df79290894fa7213f1a1855c29a177a898bd94e67bd86cd944f"
	deleteLog3Root    = "0972d52b9c5a49a54287486521fc89f52a15fc1313f153daea8afd8b9cf05660"
	testStartTime     = "2026-04-22T02:05:00.000Z"
	testEndTime       = "2026-04-22T02:06:00.000Z"
	testCreatedAt     = "2026-04-22T02:06:01.000Z"
	testTxID          = "tx-create-batch"
	testChaincodeName = "log-evidence"
)

func TestCreateAndGetBatchEvidence(t *testing.T) {
	stub := newMockStub(t)
	res := invoke(t, stub, testTxID, createBatchEvidenceFunc, validCreateInput(t))
	var created CreateBatchEvidenceResult
	mustUnmarshal(t, res.Payload, &created)

	if created.BatchID != testBatchID {
		t.Fatalf("unexpected batch_id: %s", created.BatchID)
	}
	if created.TxID != testTxID {
		t.Fatalf("unexpected tx_id: %s", created.TxID)
	}
	if _, err := time.Parse(utcMillisLayout, created.CreatedAt); err != nil {
		t.Fatalf("unexpected created_at: %s", created.CreatedAt)
	}

	state, err := stub.GetState(stateKey(testBatchID))
	if err != nil {
		t.Fatalf("GetState failed: %v", err)
	}
	if len(state) == 0 {
		t.Fatalf("expected state at key %s", stateKey(testBatchID))
	}
	var evidence BatchEvidence
	mustUnmarshal(t, state, &evidence)
	if evidence.DocType != docTypeBatchEvidence {
		t.Fatalf("unexpected doc_type: %s", evidence.DocType)
	}
	if evidence.MerkleRoot != testMerkleRoot {
		t.Fatalf("unexpected merkle_root: %s", evidence.MerkleRoot)
	}

	getRes := invoke(t, stub, "tx-get", getBatchEvidenceFunc, testBatchID)
	var got BatchEvidence
	mustUnmarshal(t, getRes.Payload, &got)
	if got.BatchID != testBatchID || got.TxID != testTxID {
		t.Fatalf("unexpected fetched evidence: %+v", got)
	}
}

func TestCreateBatchEvidenceRejectsDuplicate(t *testing.T) {
	stub := newMockStub(t)
	invoke(t, stub, testTxID, createBatchEvidenceFunc, validCreateInput(t))
	res := invokeExpectError(t, stub, "tx-dup", createBatchEvidenceFunc, validCreateInput(t))
	assertMessageContains(t, res.Message, "already exists")
}

func TestCreateBatchEvidenceValidationFailures(t *testing.T) {
	tests := []struct {
		name    string
		mutate  func(map[string]any)
		message string
	}{
		{
			name: "empty root",
			mutate: func(input map[string]any) {
				input["merkle_root"] = ""
			},
			message: "merkle_root",
		},
		{
			name: "uppercase root",
			mutate: func(input map[string]any) {
				input["merkle_root"] = strings.ToUpper(testMerkleRoot)
			},
			message: "merkle_root",
		},
		{
			name: "root with prefix",
			mutate: func(input map[string]any) {
				input["merkle_root"] = "0x" + testMerkleRoot
			},
			message: "merkle_root",
		},
		{
			name: "zero log count",
			mutate: func(input map[string]any) {
				input["log_count"] = 0
			},
			message: "log_count",
		},
		{
			name: "invalid window",
			mutate: func(input map[string]any) {
				input["end_time"] = "2026-04-22T02:07:00.000Z"
			},
			message: "60 seconds",
		},
		{
			name: "missing millis",
			mutate: func(input map[string]any) {
				input["start_time"] = "2026-04-22T02:05:00Z"
			},
			message: "start_time",
		},
		{
			name: "not UTC",
			mutate: func(input map[string]any) {
				input["start_time"] = "2026-04-22T10:05:00.000+08:00"
			},
			message: "start_time",
		},
		{
			name: "source mismatch",
			mutate: func(input map[string]any) {
				input["source"] = "nginx-demo"
			},
			message: "source",
		},
		{
			name: "schema version",
			mutate: func(input map[string]any) {
				input["schema_version"] = 2
			},
			message: "schema_version",
		},
		{
			name: "hash algorithm",
			mutate: func(input map[string]any) {
				input["hash_algorithm"] = "SHA512"
			},
			message: "hash_algorithm",
		},
		{
			name: "canonicalization version",
			mutate: func(input map[string]any) {
				input["canonicalization_version"] = "clog-v2"
			},
			message: "canonicalization_version",
		},
		{
			name: "forbidden tx id",
			mutate: func(input map[string]any) {
				input["tx_id"] = "client-supplied"
			},
			message: "forbidden input field: tx_id",
		},
		{
			name: "forbidden created at",
			mutate: func(input map[string]any) {
				input["created_at"] = testCreatedAt
			},
			message: "forbidden input field: created_at",
		},
		{
			name: "forbidden source node",
			mutate: func(input map[string]any) {
				input["source_node"] = "node1"
			},
			message: "forbidden input field: source_node",
		},
		{
			name: "state key collision punctuation",
			mutate: func(input map[string]any) {
				input["batch_id"] = "bch_v1_tomcat-cve-2017-12615:bad_20260422T020500Z"
			},
			message: "batch_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stub := newMockStub(t)
			input := validCreateInputMap()
			tt.mutate(input)
			res := invokeExpectError(t, stub, "tx-"+tt.name, createBatchEvidenceFunc, marshalMap(t, input))
			assertMessageContains(t, res.Message, tt.message)
		})
	}
}

func TestGetBatchEvidenceFailures(t *testing.T) {
	stub := newMockStub(t)
	res := invokeExpectError(t, stub, "tx-get-missing", getBatchEvidenceFunc, testBatchID)
	assertMessageContains(t, res.Message, "not found")

	res = invokeExpectError(t, stub, "tx-get-invalid", getBatchEvidenceFunc, "bad:id")
	assertMessageContains(t, res.Message, "batch_id")
}

func TestVerifyBatchRoot(t *testing.T) {
	stub := newMockStub(t)
	invoke(t, stub, testTxID, createBatchEvidenceFunc, validCreateInput(t))

	matchRes := invoke(t, stub, "tx-verify-match", verifyBatchRootFunc, testBatchID, testMerkleRoot)
	var match VerifyBatchRootResult
	mustUnmarshal(t, matchRes.Payload, &match)
	if !match.Matched {
		t.Fatalf("expected matched=true: %+v", match)
	}
	if match.TxID != "tx-verify-match" {
		t.Fatalf("unexpected verify tx_id: %s", match.TxID)
	}

	mismatchRes := invoke(t, stub, "tx-verify-mismatch", verifyBatchRootFunc, testBatchID, deleteLog3Root)
	var mismatch VerifyBatchRootResult
	mustUnmarshal(t, mismatchRes.Payload, &mismatch)
	if mismatch.Matched {
		t.Fatalf("expected matched=false: %+v", mismatch)
	}
	if mismatch.ExpectedMerkleRoot != testMerkleRoot || mismatch.ActualMerkleRoot != deleteLog3Root {
		t.Fatalf("unexpected roots: %+v", mismatch)
	}

	errRes := invokeExpectError(t, stub, "tx-verify-invalid", verifyBatchRootFunc, testBatchID, "bad-root")
	assertMessageContains(t, errRes.Message, "merkle_root")
}

func TestArgumentCountAndUnknownFunction(t *testing.T) {
	stub := newMockStub(t)
	cases := []struct {
		name string
		args []string
	}{
		{"create arg count", []string{createBatchEvidenceFunc}},
		{"get arg count", []string{getBatchEvidenceFunc}},
		{"time range arg count", []string{queryByTimeRangeFunc, testStartTime}},
		{"source arg count", []string{queryBySourceFunc}},
		{"verify arg count", []string{verifyBatchRootFunc, testBatchID}},
		{"unknown function", []string{"NoSuchFunction"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := stub.MockInvoke("tx-"+tc.name, stringArgs(tc.args...))
			if res.Status == shim.OK {
				t.Fatalf("expected error for %s", tc.name)
			}
		})
	}
}

func TestQueryValidation(t *testing.T) {
	stub := newMockStub(t)

	res := invokeExpectError(t, stub, "tx-range-bad-order", queryByTimeRangeFunc, testEndTime, testStartTime)
	assertMessageContains(t, res.Message, "startTime")

	res = invokeExpectError(t, stub, "tx-range-bad-format", queryByTimeRangeFunc, "2026-04-22T02:00:00Z", testEndTime)
	assertMessageContains(t, res.Message, "start_time")

	res = invokeExpectError(t, stub, "tx-source-empty", queryBySourceFunc, "")
	assertMessageContains(t, res.Message, "source")

	res = invokeExpectError(t, stub, "tx-source-invalid", queryBySourceFunc, "Tomcat")
	assertMessageContains(t, res.Message, "source")
}

func TestSortBatchEvidence(t *testing.T) {
	records := []BatchEvidence{
		{BatchID: "bch_v1_tomcat-cve-2017-12615_20260422T020600Z", StartTime: "2026-04-22T02:06:00.000Z"},
		{BatchID: "bch_v1_tomcat-cve-2017-12615_20260422T020500Z", StartTime: "2026-04-22T02:05:00.000Z"},
		{BatchID: "bch_v1_apache-demo_20260422T020500Z", StartTime: "2026-04-22T02:05:00.000Z"},
	}
	sortBatchEvidence(records)
	got := []string{records[0].BatchID, records[1].BatchID, records[2].BatchID}
	want := []string{
		"bch_v1_apache-demo_20260422T020500Z",
		"bch_v1_tomcat-cve-2017-12615_20260422T020500Z",
		"bch_v1_tomcat-cve-2017-12615_20260422T020600Z",
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected order: got %v want %v", got, want)
		}
	}
}

func newMockStub(t *testing.T) *shimtest.MockStub {
	t.Helper()
	stub := shimtest.NewMockStub(testChaincodeName, new(EvidenceChaincode))
	res := stub.MockInit("tx-init", nil)
	if res.Status != shim.OK {
		t.Fatalf("init failed: %s", res.Message)
	}
	return stub
}

func invoke(t *testing.T, stub *shimtest.MockStub, txID string, function string, args ...string) *peerResponse {
	t.Helper()
	res := stub.MockInvoke(txID, stringArgs(append([]string{function}, args...)...))
	if res.Status != shim.OK {
		t.Fatalf("invoke %s failed: %s", function, res.Message)
	}
	return &peerResponse{Status: res.Status, Message: res.Message, Payload: res.Payload}
}

func invokeExpectError(t *testing.T, stub *shimtest.MockStub, txID string, function string, args ...string) *peerResponse {
	t.Helper()
	res := stub.MockInvoke(txID, stringArgs(append([]string{function}, args...)...))
	if res.Status == shim.OK {
		t.Fatalf("invoke %s unexpectedly succeeded: %s", function, string(res.Payload))
	}
	return &peerResponse{Status: res.Status, Message: res.Message, Payload: res.Payload}
}

type peerResponse struct {
	Status  int32
	Message string
	Payload []byte
}

func stringArgs(args ...string) [][]byte {
	out := make([][]byte, len(args))
	for i, arg := range args {
		out[i] = []byte(arg)
	}
	return out
}

func validCreateInput(t *testing.T) string {
	t.Helper()
	return marshalMap(t, validCreateInputMap())
}

func validCreateInputMap() map[string]any {
	return map[string]any{
		"batch_id":                 testBatchID,
		"merkle_root":              testMerkleRoot,
		"log_count":                3,
		"start_time":               testStartTime,
		"end_time":                 testEndTime,
		"source":                   "tomcat-cve-2017-12615",
		"schema_version":           schemaVersion,
		"hash_algorithm":           hashAlgorithm,
		"canonicalization_version": canonicalizationVersion,
	}
}

func marshalMap(t *testing.T, value map[string]any) string {
	t.Helper()
	bytes, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	return string(bytes)
}

func mustUnmarshal(t *testing.T, payload []byte, target any) {
	t.Helper()
	if err := json.Unmarshal(payload, target); err != nil {
		t.Fatalf("unmarshal failed: %v\npayload=%s", err, string(payload))
	}
}

func assertMessageContains(t *testing.T, message string, want string) {
	t.Helper()
	if !strings.Contains(message, want) {
		t.Fatalf("expected error message %q to contain %q", message, want)
	}
}
