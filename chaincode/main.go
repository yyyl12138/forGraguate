package main

import (
	"log"

	"github.com/hyperledger/fabric-chaincode-go/shim"
)

func main() {
	if err := shim.Start(new(EvidenceChaincode)); err != nil {
		log.Fatalf("failed to start log evidence chaincode: %v", err)
	}
}
