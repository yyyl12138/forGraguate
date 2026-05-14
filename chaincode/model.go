package main

const (
	docTypeBatchEvidence      = "BatchEvidence"
	schemaVersion             = 1
	hashAlgorithm             = "SHA-256"
	canonicalizationVersion   = "clog-v1"
	stateKeyPrefix            = "batch:"
	createBatchEvidenceFunc   = "CreateBatchEvidence"
	getBatchEvidenceFunc      = "GetBatchEvidence"
	queryByTimeRangeFunc      = "QueryBatchEvidenceByTimeRange"
	queryBySourceFunc         = "QueryBatchEvidenceBySource"
	verifyBatchRootFunc       = "VerifyBatchRoot"
	utcMillisLayout           = "2006-01-02T15:04:05.000Z"
	forbiddenInputFieldTxID   = "tx_id"
	forbiddenInputFieldDoc    = "doc_type"
	forbiddenInputFieldCreate = "created_at"
)

type BatchEvidenceInput struct {
	BatchID                 string `json:"batch_id"`
	MerkleRoot              string `json:"merkle_root"`
	LogCount                int    `json:"log_count"`
	StartTime               string `json:"start_time"`
	EndTime                 string `json:"end_time"`
	Source                  string `json:"source"`
	SchemaVersion           int    `json:"schema_version"`
	HashAlgorithm           string `json:"hash_algorithm"`
	CanonicalizationVersion string `json:"canonicalization_version"`
}

type BatchEvidence struct {
	DocType                 string `json:"doc_type"`
	BatchID                 string `json:"batch_id"`
	MerkleRoot              string `json:"merkle_root"`
	LogCount                int    `json:"log_count"`
	StartTime               string `json:"start_time"`
	EndTime                 string `json:"end_time"`
	Source                  string `json:"source"`
	SchemaVersion           int    `json:"schema_version"`
	HashAlgorithm           string `json:"hash_algorithm"`
	CanonicalizationVersion string `json:"canonicalization_version"`
	CreatedAt               string `json:"created_at"`
	TxID                    string `json:"tx_id"`
}

type CreateBatchEvidenceResult struct {
	BatchID   string `json:"batch_id"`
	TxID      string `json:"tx_id"`
	CreatedAt string `json:"created_at"`
}

type VerifyBatchRootResult struct {
	BatchID            string `json:"batch_id"`
	ExpectedMerkleRoot string `json:"expected_merkle_root"`
	ActualMerkleRoot   string `json:"actual_merkle_root"`
	Matched            bool   `json:"matched"`
	TxID               string `json:"tx_id"`
}
