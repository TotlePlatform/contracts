// SPDX-License-Identifier: UNLICENSED
/*

  Copyright 2018 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity 0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LibFillResults {
    struct FillResults {
        uint256 makerAssetFilledAmount;  // Total amount of makerAsset(s) filled.
        uint256 takerAssetFilledAmount;  // Total amount of takerAsset(s) filled.
        uint256 makerFeePaid;            // Total amount of ZRX paid by maker(s) to feeRecipient(s).
        uint256 takerFeePaid;            // Total amount of ZRX paid by taker to feeRecipients(s).
    }

    struct MatchedFillResults {
        FillResults left;                    // Amounts filled and fees paid of left order.
        FillResults right;                   // Amounts filled and fees paid of right order.
        uint256 leftMakerAssetSpreadAmount;  // Spread between price of left and right order, denominated in the left order's makerAsset, paid to taker.
    }

    /// @dev Adds properties of both FillResults instances.
    ///      Modifies the first FillResults instance specified.
    /// @param totalFillResults Fill results instance that will be added onto.
    /// @param singleFillResults Fill results instance that will be added to totalFillResults.
    function addFillResults(FillResults memory totalFillResults, FillResults memory singleFillResults)
        internal
        pure
    {
        totalFillResults.makerAssetFilledAmount = SafeMath.add(totalFillResults.makerAssetFilledAmount, singleFillResults.makerAssetFilledAmount);
        totalFillResults.takerAssetFilledAmount = SafeMath.add(totalFillResults.takerAssetFilledAmount, singleFillResults.takerAssetFilledAmount);
        totalFillResults.makerFeePaid = SafeMath.add(totalFillResults.makerFeePaid, singleFillResults.makerFeePaid);
        totalFillResults.takerFeePaid = SafeMath.add(totalFillResults.takerFeePaid, singleFillResults.takerFeePaid);
    }
}
