// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;


contract Migrations {
  address public owner;
  uint public last_completed_migration;  //solhint-disable var-name-mixedcase

  modifier restricted() {
    if (msg.sender == owner) _;
  }

  constructor() {
    owner = msg.sender;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }

  function upgrade(address newAddress) public restricted {
    Migrations upgraded = Migrations(newAddress);
    upgraded.setCompleted(last_completed_migration);
  }
}
