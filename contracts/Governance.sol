// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Governance is ERC20 {

  /*
   * State Variables
  */

  constructor() 
  ERC20("Rila", "RIL")
  {}

  struct Account {
    uint256 aVER;
    uint64 nonce;
    mapping (uint64 => Deposit) d; // For now, let's assume a subgraph/IPFS stores deposit data.
  }

  struct Deposit {
    uint256 amount;
    uint256 timestamp;
    uint256 lockedUntil;
    uint256 dVER;
  }

  struct Proposal {
    bool status;
    bool committed;
    address proposer;
    address executionContract;
    bytes4 selector;
    bytes data;
    string proposalURI;
    uint256 favor;
    uint256 passAmount;
    uint256 dateProposed;
    uint256 dateExpired;
  }

  mapping (address => Account) acc;
  mapping (uint128 => Proposal) proposal;

  uint256 totalVER;
  uint128 proposalNonce;

  /*
   * Governance Functions
  */

  function stake(uint256 amount, uint256 numWeeks) public returns (bool) {
    uint256 escrowAmount = ((numWeeks * 5)/4) * amount; // This should be changed to better scale (later)
    
    transferFrom(msg.sender, address(this), amount);
    
    acc[msg.sender].d[acc[msg.sender].nonce] = Deposit(amount, block.timestamp, block.timestamp + (604800 * numWeeks), escrowAmount);
    acc[msg.sender].aVER += escrowAmount;
    totalVER += escrowAmount;
    acc[msg.sender].nonce++;
    
    return true;
  }

  function unstake(uint64 depositID) public returns (bool) {
    require(acc[msg.sender].d[depositID].lockedUntil != uint128(0), "Deposit does not exist.");
    require(acc[msg.sender].d[depositID].lockedUntil <= block.timestamp, "Deposit is not ready to be claimed.");
    
    transfer(msg.sender, acc[msg.sender].d[depositID].amount);
    acc[msg.sender].aVER -= acc[msg.sender].d[depositID].dVER;
    
    delete acc[msg.sender].d[depositID];
    
    return true;
  }

  function submitProposal
  (
    string calldata proposalLink, 
    address executionContract,
    bytes4 header, 
    bytes calldata data
  ) public {
    
    require(acc[msg.sender].aVER * 1000 > totalVER, "Insufficient voting power."); // Proposer has >= 0.1% of all VER

    // Notice how even if the proposer has > 33% of totalVER, the proposal won't automatically be passed unless another votes
    proposal[proposalNonce] = Proposal
    (
      false, 
      false, 
      msg.sender, 
      executionContract, 
      header,
      data,
      proposalLink, 
      acc[msg.sender].aVER, 
      (totalVER * 2)/3, 
      block.timestamp, 
      block.timestamp + 604800
    );

    proposalNonce++;
  }

  function vote(uint128 proposalID) public {
    require(proposal[proposalID].favor > 0, "Proposal does not exist.");
    require(proposal[proposalID].dateExpired >= block.timestamp, "Proposal is already expired.");

    proposal[proposalNonce].favor += acc[msg.sender].aVER;

    if (passable(proposalID)) proposal[proposalID].status = true;
  }

  function commit(uint128 proposalID) external returns (bytes memory) {
    require(proposal[proposalID].status, "Proposal did not pass.");
    require(!proposal[proposalID].committed, "Proposal action already committed on-chain.");

    // We can further improve this function by adding special state variables on our contract.
    proposal[proposalID].committed = true;
    (bool success, bytes memory data) = proposal[proposalID].executionContract.delegatecall
    (
      abi.encodeWithSelector
      (
        proposal[proposalID].selector, 
        proposal[proposalID].data
      )
    );
    require(success, "Execution unsuccessful.");

    return data;
  }

  /*
   * Helper Functions
  */
  
  function passable(uint128 proposalID) public view returns (bool) {
    return ((proposal[proposalID].favor * 3)/2) > proposal[proposalID].passAmount;
  }

  function depositByAddressAndID(address account, uint64 depositID) public view returns (Deposit memory) {
    return acc[account].d[depositID];
  }

}
