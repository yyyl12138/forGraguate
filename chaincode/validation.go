package main

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
)

var (
	batchIDPattern    = regexp.MustCompile(`^bch_v1_[a-z0-9][a-z0-9-]*_[0-9]{8}T[0-9]{6}Z$`)
	sourcePattern     = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)
	merkleRootPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
	timePattern       = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`)
)

func parseBatchEvidenceInput(raw string) (BatchEvidenceInput, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal([]byte(raw), &fields); err != nil {
		return BatchEvidenceInput{}, fmt.Errorf("invalid batch evidence JSON: %w", err)
	}

	for _, field := range []string{
		forbiddenInputFieldDoc,
		forbiddenInputFieldCreate,
		forbiddenInputFieldTxID,
		"raw_message",
		"normalized_message",
		"leaf_hash",
		"source_node",
		"chain_tx_id",
		"mysql_id",
	} {
		if _, ok := fields[field]; ok {
			return BatchEvidenceInput{}, fmt.Errorf("forbidden input field: %s", field)
		}
	}

	var input BatchEvidenceInput
	if err := json.Unmarshal([]byte(raw), &input); err != nil {
		return BatchEvidenceInput{}, fmt.Errorf("invalid batch evidence input: %w", err)
	}
	return input, nil
}

func validateBatchEvidenceInput(input BatchEvidenceInput) error {
	if !batchIDPattern.MatchString(input.BatchID) {
		return fmt.Errorf("invalid batch_id: %s", input.BatchID)
	}
	if !merkleRootPattern.MatchString(input.MerkleRoot) {
		return fmt.Errorf("invalid merkle_root: %s", input.MerkleRoot)
	}
	if input.LogCount <= 0 {
		return fmt.Errorf("invalid log_count: must be greater than 0")
	}
	if !sourcePattern.MatchString(input.Source) {
		return fmt.Errorf("invalid source: %s", input.Source)
	}
	if sourceFromBatchID(input.BatchID) != input.Source {
		return fmt.Errorf("invalid source: does not match batch_id")
	}
	if input.SchemaVersion != schemaVersion {
		return fmt.Errorf("invalid schema_version: %d", input.SchemaVersion)
	}
	if input.HashAlgorithm != hashAlgorithm {
		return fmt.Errorf("invalid hash_algorithm: %s", input.HashAlgorithm)
	}
	if input.CanonicalizationVersion != canonicalizationVersion {
		return fmt.Errorf("invalid canonicalization_version: %s", input.CanonicalizationVersion)
	}

	start, err := parseUTCMillis(input.StartTime, "start_time")
	if err != nil {
		return err
	}
	end, err := parseUTCMillis(input.EndTime, "end_time")
	if err != nil {
		return err
	}
	if !start.Before(end) {
		return fmt.Errorf("invalid time window: start_time must be before end_time")
	}
	if end.Sub(start) != time.Minute {
		return fmt.Errorf("invalid time window: must be exactly 60 seconds")
	}
	return nil
}

func validateBatchID(batchID string) error {
	if !batchIDPattern.MatchString(batchID) {
		return fmt.Errorf("invalid batch_id: %s", batchID)
	}
	return nil
}

func validateSource(source string) error {
	if !sourcePattern.MatchString(source) {
		return fmt.Errorf("invalid source: %s", source)
	}
	return nil
}

func validateMerkleRoot(root string) error {
	if !merkleRootPattern.MatchString(root) {
		return fmt.Errorf("invalid merkle_root: %s", root)
	}
	return nil
}

func parseUTCMillis(value string, fieldName string) (time.Time, error) {
	if !timePattern.MatchString(value) {
		return time.Time{}, fmt.Errorf("invalid %s: must use UTC millisecond format", fieldName)
	}
	parsed, err := time.Parse(utcMillisLayout, value)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid %s: %w", fieldName, err)
	}
	return parsed, nil
}

func stateKey(batchID string) string {
	return stateKeyPrefix + batchID
}

func sourceFromBatchID(batchID string) string {
	const prefix = "bch_v1_"
	if !strings.HasPrefix(batchID, prefix) {
		return ""
	}
	rest := strings.TrimPrefix(batchID, prefix)
	idx := strings.LastIndex(rest, "_")
	if idx <= 0 {
		return ""
	}
	return rest[:idx]
}

func formatTxTimestamp(stub shim.ChaincodeStubInterface) (string, error) {
	ts, err := stub.GetTxTimestamp()
	if err != nil {
		return "", fmt.Errorf("failed to read tx timestamp: %w", err)
	}
	txTime := time.Unix(ts.Seconds, int64(ts.Nanos)).UTC()
	return txTime.Format(utcMillisLayout), nil
}
