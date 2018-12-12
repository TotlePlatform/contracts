pragma solidity 0.4.25;

contract ErrorReporter {
    function revertTx(string reason) public pure {
        revert(reason);
    }
}
