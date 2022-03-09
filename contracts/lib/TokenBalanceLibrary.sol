// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

library TokenBalanceLibrary {
    struct TokenBalance {
        address tokenAddress;
        uint256 balance;
    }

    /*
     * Internal functions
     */
     
    /// @dev Finds token entry in balances array
    /// @param balances Array of token balance entries
    /// @param token The address of the token to find the entry for. If it's not found, it will create a new entry and return that index
    /// @return tokenEntry The index that this tokens entry can be found at

    function findToken(TokenBalance[] memory balances, address token)
        internal
        pure
        returns (uint256 tokenEntry)
    {
        for (uint256 index = 0; index < balances.length; index++) {
            if (balances[index].tokenAddress == token) {
                return index;
            } else if (
                index != 0 && balances[index].tokenAddress == address(0x0)
            ) {
                balances[index] = TokenBalance(token, 0);
                return index;
            }
        }
    }

    /// @dev Adds an amount of a token to the balances array by token address. Automatically adds entry if it doesn't exist
    /// @param balances Array of token balances to add to
    /// @param token The address of the token to add balance to
    /// @param amountToAdd Amount of the token to add to balance
    function addBalance(
        TokenBalance[] memory balances,
        address token,
        uint256 amountToAdd
    ) internal pure {
        uint256 tokenIndex = findToken(balances, token);
        addBalance(balances, tokenIndex, amountToAdd);
    }

    /// @dev Adds an amount of a token to the balances array by token index
    /// @param balances Array of token balances to add to
    /// @param tokenIndex The index of the token to add balance to
    /// @param amountToAdd Amount of the token to add to balance
    function addBalance(
        TokenBalance[] memory balances,
        uint256 tokenIndex,
        uint256 amountToAdd
    ) internal pure {
        balances[tokenIndex].balance += amountToAdd;
    }

    /// @dev Removes an amount of a token from the balances array by token address
    /// @param balances Array of token balances to remove from
    /// @param token The address of the token to remove balance from
    /// @param amountToRemove Amount of the token to remove from balance
    function removeBalance(
        TokenBalance[] memory balances,
        address token,
        uint256 amountToRemove
    ) internal pure {
        uint256 tokenIndex = findToken(balances, token);
        removeBalance(balances, tokenIndex, amountToRemove);
    }

    /// @dev Removes an amount of a token from the balances array by token index
    /// @param balances Array of token balances to remove from
    /// @param tokenIndex The index of the token to remove balance from
    /// @param amountToRemove Amount of the token to remove from balance
    function removeBalance(
        TokenBalance[] memory balances,
        uint256 tokenIndex,
        uint256 amountToRemove
    ) internal pure {
        balances[tokenIndex].balance -= amountToRemove;
    }
}
