package main

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	pb "github.com/hyperledger/fabric-protos-go/peer"
)

type EvidenceChaincode struct{}

func (cc *EvidenceChaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {
	return shim.Success(nil)
}

func (cc *EvidenceChaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	function, args := stub.GetFunctionAndParameters()

	var (
		payload []byte
		err     error
	)

	switch function {
	case createBatchEvidenceFunc:
		payload, err = cc.CreateBatchEvidence(stub, args)
	case getBatchEvidenceFunc:
		payload, err = cc.GetBatchEvidence(stub, args)
	case queryByTimeRangeFunc:
		payload, err = cc.QueryBatchEvidenceByTimeRange(stub, args)
	case queryBySourceFunc:
		payload, err = cc.QueryBatchEvidenceBySource(stub, args)
	case verifyBatchRootFunc:
		payload, err = cc.VerifyBatchRoot(stub, args)
	default:
		err = fmt.Errorf("unknown function: %s", function)
	}

	if err != nil {
		return shim.Error(err.Error())
	}
	return shim.Success(payload)
}

func (cc *EvidenceChaincode) CreateBatchEvidence(stub shim.ChaincodeStubInterface, args []string) ([]byte, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("%s expects 1 argument", createBatchEvidenceFunc)
	}

	input, err := parseBatchEvidenceInput(args[0])
	if err != nil {
		return nil, err
	}
	if err := validateBatchEvidenceInput(input); err != nil {
		return nil, err
	}

	key := stateKey(input.BatchID)
	existing, err := stub.GetState(key)
	if err != nil {
		return nil, fmt.Errorf("failed to read existing batch evidence: %w", err)
	}
	if len(existing) > 0 {
		return nil, fmt.Errorf("batch evidence already exists: %s", input.BatchID)
	}

	createdAt, err := formatTxTimestamp(stub)
	if err != nil {
		return nil, err
	}

	evidence := BatchEvidence{
		DocType:                 docTypeBatchEvidence,
		BatchID:                 input.BatchID,
		MerkleRoot:              input.MerkleRoot,
		LogCount:                input.LogCount,
		StartTime:               input.StartTime,
		EndTime:                 input.EndTime,
		Source:                  input.Source,
		SchemaVersion:           input.SchemaVersion,
		HashAlgorithm:           input.HashAlgorithm,
		CanonicalizationVersion: input.CanonicalizationVersion,
		CreatedAt:               createdAt,
		TxID:                    stub.GetTxID(),
	}

	stateBytes, err := json.Marshal(evidence)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize batch evidence: %w", err)
	}
	if err := stub.PutState(key, stateBytes); err != nil {
		return nil, fmt.Errorf("failed to write batch evidence: %w", err)
	}

	return json.Marshal(CreateBatchEvidenceResult{
		BatchID:   evidence.BatchID,
		TxID:      evidence.TxID,
		CreatedAt: evidence.CreatedAt,
	})
}

func (cc *EvidenceChaincode) GetBatchEvidence(stub shim.ChaincodeStubInterface, args []string) ([]byte, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("%s expects 1 argument", getBatchEvidenceFunc)
	}
	evidence, err := getBatchEvidenceByID(stub, args[0])
	if err != nil {
		return nil, err
	}
	return json.Marshal(evidence)
}

func (cc *EvidenceChaincode) QueryBatchEvidenceByTimeRange(stub shim.ChaincodeStubInterface, args []string) ([]byte, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("%s expects 2 arguments", queryByTimeRangeFunc)
	}
	startTime := args[0]
	endTime := args[1]

	start, err := parseUTCMillis(startTime, "start_time")
	if err != nil {
		return nil, err
	}
	end, err := parseUTCMillis(endTime, "end_time")
	if err != nil {
		return nil, err
	}
	if !start.Before(end) {
		return nil, fmt.Errorf("invalid time range: startTime must be before endTime")
	}

	query := map[string]any{
		"selector": map[string]any{
			"doc_type": docTypeBatchEvidence,
			"start_time": map[string]string{
				"$gte": startTime,
				"$lt":  endTime,
			},
		},
	}
	return queryBatchEvidence(stub, query)
}

func (cc *EvidenceChaincode) QueryBatchEvidenceBySource(stub shim.ChaincodeStubInterface, args []string) ([]byte, error) {
	if len(args) != 1 {
		return nil, fmt.Errorf("%s expects 1 argument", queryBySourceFunc)
	}
	source := args[0]
	if err := validateSource(source); err != nil {
		return nil, err
	}

	query := map[string]any{
		"selector": map[string]any{
			"doc_type": docTypeBatchEvidence,
			"source":   source,
		},
	}
	return queryBatchEvidence(stub, query)
}

func (cc *EvidenceChaincode) VerifyBatchRoot(stub shim.ChaincodeStubInterface, args []string) ([]byte, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("%s expects 2 arguments", verifyBatchRootFunc)
	}
	batchID := args[0]
	actualRoot := args[1]
	if err := validateMerkleRoot(actualRoot); err != nil {
		return nil, err
	}

	evidence, err := getBatchEvidenceByID(stub, batchID)
	if err != nil {
		return nil, err
	}

	return json.Marshal(VerifyBatchRootResult{
		BatchID:            evidence.BatchID,
		ExpectedMerkleRoot: evidence.MerkleRoot,
		ActualMerkleRoot:   actualRoot,
		Matched:            evidence.MerkleRoot == actualRoot,
		TxID:               stub.GetTxID(),
	})
}

func getBatchEvidenceByID(stub shim.ChaincodeStubInterface, batchID string) (BatchEvidence, error) {
	if err := validateBatchID(batchID); err != nil {
		return BatchEvidence{}, err
	}
	state, err := stub.GetState(stateKey(batchID))
	if err != nil {
		return BatchEvidence{}, fmt.Errorf("failed to read batch evidence: %w", err)
	}
	if len(state) == 0 {
		return BatchEvidence{}, fmt.Errorf("batch evidence not found: %s", batchID)
	}

	var evidence BatchEvidence
	if err := json.Unmarshal(state, &evidence); err != nil {
		return BatchEvidence{}, fmt.Errorf("failed to deserialize batch evidence: %w", err)
	}
	return evidence, nil
}

func queryBatchEvidence(stub shim.ChaincodeStubInterface, query map[string]any) ([]byte, error) {
	queryBytes, err := json.Marshal(query)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize rich query: %w", err)
	}

	iter, err := stub.GetQueryResult(string(queryBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to execute rich query: %w", err)
	}
	defer iter.Close()

	var records []BatchEvidence
	for iter.HasNext() {
		kv, err := iter.Next()
		if err != nil {
			return nil, fmt.Errorf("failed to read rich query result: %w", err)
		}
		var evidence BatchEvidence
		if err := json.Unmarshal(kv.Value, &evidence); err != nil {
			return nil, fmt.Errorf("failed to deserialize rich query result: %w", err)
		}
		if evidence.DocType != docTypeBatchEvidence {
			continue
		}
		records = append(records, evidence)
	}

	sortBatchEvidence(records)
	return json.Marshal(records)
}

func sortBatchEvidence(records []BatchEvidence) {
	sort.Slice(records, func(i, j int) bool {
		if records[i].StartTime == records[j].StartTime {
			return records[i].BatchID < records[j].BatchID
		}
		return records[i].StartTime < records[j].StartTime
	})
}
