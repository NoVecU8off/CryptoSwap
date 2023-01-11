/* Copyright 2022 Andrey Novikov

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

// SPDX-License-Identifier: Apache-2.0

/*_________________________________________CRYPTOTRON_________________________________________*/

pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "hardhat/console.sol";

/**
* @dev interface of NFT smart contract (aka the Ticket), that provides functionality 
* @dev for entering the draw and setting the states for both contracts.
*/
interface CryptotronTicketInterface {
    /**
   * @dev returns the owner address of a specific token.
   */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
   * @dev returns the amount of supported tokens within current contract.
   */
    function getSoldTicketsCount() external view returns (uint256);

    /**
   * @dev sets the time of the next draw.
   */
    function setDrawDate(uint256 _drawDate) external;

    /**
   * @dev sets the winner tokenId.
   */
    function setWinnerId(uint256 _winnerId) external;

    /**
   * activate different states of NFT contract.
   */
    function setStateOpen() external;

    function setStateProcessing() external;

    function setStateOver() external;

    function setStateRefunded() external;
}

/**
 * @dev Interface of ERC20 token that's used for winnings currency in this 
 * @dev project.
 */
interface IERC20 {
    /**
   * @dev Returns the amount of tokens in existence.
   */
    function totalSupply() external view returns (uint256);

    /**
   * @dev Returns the amount of tokens owned by `account`.
   */
    function balanceOf(address account) external view returns (uint256);

    /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * IMPORTANT: Beware that changing an allowance with this method brings the risk
   * that someone may use both the old and the new allowance by unfortunate
   * transaction ordering. One possible solution to mitigate this race
   * condition is to first reduce the spender's allowance to 0 and set the
   * desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   *
   * Emits an {Approval} event.
   */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to
   * another (`to`).
   *
   * Note that `value` may be zero.
   */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


/**
* @dev Errors.
*/
error UE(uint256 currentBalance, uint256 numPlayers, bool isDrawProcessActive);
error TE();
error SE();
error FE();
error DE();
error OE();
error ZE();


/**@title Cryptotron project
* @author Andrey Novikov
*/
contract CryptotronLottery is VRFConsumerBaseV2, AutomationCompatibleInterface {

    /**
    * @dev Variables.
    */
    // VRF related
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 4;
    
    // VRF unrelated
    uint256 private constant ONE_DAY_IN_SEC = 86400;
    address payable public owner;
    address private nullAddress = address(0x0);
    address private nftAddress;
    address private rewardTokenAddress;
    uint256 private _drawDate;
    bool private isDrawFailed;
    bool private isDrawProcessActive;
    bool private isLotteryActive;

    /**
   * @dev Events for the future dev.
   */
    event RandomWordsRequested(uint256 indexed requestId);
    event PlayerRegistered(address indexed player);
    event WinnerPicked(address indexed winner);
    event EmergencyRefund(address indexed refunder);
    event FailureWasReset();
    event NativeCoinFunded(address indexed funder);
    event TokensLanded(address indexed funder, uint256 indexed amount);
    event TokensTransfered(address indexed recipient);
    event LotteryActivated(address indexed newNftAddress, address indexed newRewardTokenAddress, uint256 indexed newDrawDate);

    /**
   * @dev Replacement for the reqire(msg.sender == owner);
   */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(failure == false);
   */
    modifier onlyIfDrawNotFailed() {
        if (isDrawFailed == true) {
            revert();
        }
        _;
    }

    modifier onlyIfLotteryIsNotActive() {
        if (isLotteryActive == true) {
            revert();
        }
        _;
    }

    modifier onlyIfLotteryIsActive() {
        if (isLotteryActive == false) {
            revert();
        }
        _;
    }

    /**
   * @dev Constructor with the arguments for the VRFConsumerBaseV2.
   */
    constructor(
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        owner = payable(msg.sender);
        nftAddress = nullAddress;
        rewardTokenAddress = nullAddress;
        isDrawProcessActive = false;
        isDrawFailed = false;
        isLotteryActive = false;
    }

    /**
   * @notice Method that is actually executed by the keepers, via the registry.
   * @notice The data returned by the checkUpkeep simulation will be passed into
   * @notice this method to actually be executed.
   * 
   * @dev calldata (aka performData) is the data which was passed back from the checkData
   * @dev simulation. If it is encoded, it can easily be decoded into other types by
   * @dev calling `abi.decode`. This data should not be trusted, and should be
   * @dev validated against the contract's current state.
   * 
   * @notice requestRandomWords (request a set of random words).
   * @dev gasLane (aka keyHash) - Corresponds to a particular oracle job which uses
   * that key for generating the VRF proof. Different keyHash's have different gas price
   * ceilings, so you can select a specific one to bound your maximum per request cost.
   * @dev i_subscriptionId  - The ID of the VRF subscription. Must be funded
   * with the minimum subscription balance required for the selected keyHash.
   * @dev REQUEST_CONFIRMATIONS - How many blocks you'd like the
   * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
   * for why you may want to request more. The acceptable range is
   * [minimumRequestBlockConfirmations, 200].
   * @dev i_callbackGasLimit - How much gas you'd like to receive in your
   * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
   * may be slightly less than this amount because of gas used calling the function
   * (argument decoding etc.), so you may need to request slightly more than you expect
   * to have inside fulfillRandomWords. The acceptable range is
   * [0, maxGasLimit]
   * @dev NUM_WORDS - The number of uint256 random values you'd like to receive
   * in your fulfillRandomWords callback. Note these numbers are expanded in a
   * secure way by the VRFCoordinator from a single random value supplied by the oracle.
   * @dev requestId - A unique identifier of the request. Can be used to match
   * a request to a response in fulfillRandomWords.
   */
    function performUpkeep(
        bytes calldata
    ) external override onlyIfLotteryIsActive onlyIfDrawNotFailed{
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert UE(
                IERC20(rewardTokenAddress).balanceOf(address(this)),
                CryptotronTicketInterface(nftAddress).getSoldTicketsCount(),
                isDrawProcessActive
            );
        }

        isDrawProcessActive = true;
        CryptotronTicketInterface(nftAddress).setStateProcessing();
        
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RandomWordsRequested(requestId);
    }

    /**
   * @dev Checker function. When Chainlink Automation calls performUpkeep
   * @dev function it calls this checker function and waits for it to return
   * @dev boolean true so performUpkeep can proceed and make request to ChainlinkVRF. 
   * @dev Params checked: current state, passed time, players amount, balance of the contract.
   */
    function checkUpkeep(
        bytes memory
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        IERC20 token = IERC20(rewardTokenAddress);
        bool timePassed = block.timestamp > _drawDate;
        bool hasPlayers = CryptotronTicketInterface(nftAddress).getSoldTicketsCount() > 0;
        bool hasBalance = token.balanceOf(address(this)) > 0;
        bool hasGasCoin = address(this).balance > 0;
        upkeepNeeded = (isLotteryActive && !isDrawProcessActive && timePassed && hasPlayers && hasBalance && hasGasCoin);
        return (upkeepNeeded, "0x0");
    }

    /**
   * @dev sets all parameters needed (including both contracts).
   */
    function activate(
        address newNftAdress,
        address newRewardTokenAddress,
        uint256 newDrawDate
    ) public onlyOwner onlyIfDrawNotFailed onlyIfLotteryIsNotActive{
            nftAddress = newNftAdress;
            rewardTokenAddress = newRewardTokenAddress;
            _drawDate = newDrawDate;

            CryptotronTicketInterface cti = CryptotronTicketInterface(nftAddress);
            cti.setDrawDate(_drawDate);
            cti.setStateOpen();

            isLotteryActive = true;
            
            emit LotteryActivated(nftAddress, rewardTokenAddress, _drawDate);
    }

    /**
   * @dev This fuction is for refunding purchased tickets to Cryptotron
   * @dev Function is public, so everyone can call it.
   * @dev Keeps track of callers of this function.
   */
    function refund() public onlyIfLotteryIsActive{
        if (isDrawFailed == true || block.timestamp > _drawDate + ONE_DAY_IN_SEC) {
            revert();
        }

        CryptotronTicketInterface cti = CryptotronTicketInterface(nftAddress);
        cti.setStateRefunded();

        IERC20 token = IERC20(rewardTokenAddress);
        if (token.balanceOf(address(this)) != 0) {
            uint256 refundAmount = (token.balanceOf(address(this)) / cti.getSoldTicketsCount());
            for (uint i = 0; i < cti.getSoldTicketsCount(); i++) {
                payable(cti.ownerOf(i)).transfer(refundAmount);
            }
        }

        isDrawFailed = false;
        reset();
        
        emit EmergencyRefund(msg.sender);
    }

    /**
   * @dev This function was made just for funding the Cryptotron for providing
   * @dev transactions (service) on current network with it's native currency.
   *
   * @notice Do not use this function to enter the Cryptotron.
   */
    function fundNativeCoin() public payable {
        emit NativeCoinFunded(msg.sender);
    }

    /**
   * @dev This function was made just for funding the Cryptotron.
   *
   * @notice You can increase lottery winnings. But it is not changing
   * @notice youre chances for the win. We are storing your address for future. :)
   *
   * @notice Do not use this function to enter the Cryptotron.
   */
    function fundRewardToken(uint256 _amount) public {
        IERC20 token = IERC20(rewardTokenAddress);
        require(_amount > 0, "");
        token.transferFrom(msg.sender, address(this), _amount);
        emit TokensLanded(msg.sender, _amount);
    }

    /**
   * @dev VRFConsumerBaseV2 expects its subcontracts to have a method with this
   * @dev signature, and will call it once it has verified the proof
   * @dev associated with the randomness. (It is triggered via a call to
   * @dev rawFulfillRandomness, below.)
   * @dev After receiving a random word (aka random number), this function will
   * @dev choose the winner and "call" him the entire balance of this contract.
   * 
   * @dev (uint256 aka requestId) the Id initially returned by requestRandomness.
   * @param randomWords the VRF output expanded to the requested number of words
   */
    function fulfillRandomWords(
        uint256, 
        uint256[] memory randomWords
    ) internal override onlyIfLotteryIsActive onlyIfDrawNotFailed {
        CryptotronTicketInterface cti = CryptotronTicketInterface(nftAddress);
        
        uint256 indexOfWinner = randomWords[0] % cti.getSoldTicketsCount() + 1;
        uint256 winnerId = indexOfWinner;
        address payable recipient = payable(cti.ownerOf(indexOfWinner));

        IERC20 token = IERC20(rewardTokenAddress);
        uint256 amount = token.balanceOf(address(this));
        (bool success) = token.transfer(recipient, amount);
        if (!success) {
            isDrawFailed = true;
            revert TE();
        }

        cti.setWinnerId(winnerId);
        cti.setStateOver();

        reset();

        emit WinnerPicked(recipient);
    }

    /**
   * @dev refreshes the states of the lottery (in case of unexpected errors
   * @dev that are not related to the logic and math of this contract).
   */
    function reset() private onlyIfDrawNotFailed onlyIfLotteryIsActive{
        nftAddress = nullAddress;
        rewardTokenAddress = nullAddress;
        isDrawProcessActive = false;
        isLotteryActive = false;
    }

    /**
   * @dev Returns the balance of the Cryptotron contract (Native).
   * 
   * @notice This funds are the "Native currency" of the Cryptotron.
   */
    function getNativeBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
   * @dev Returns the balance of the Cryptotron contract (winnings).
   * 
   * @notice This funds are the "Winnings" of the Cryptotron.
   */
    function getRewardAmount() public view returns (uint256) {
        IERC20 token = IERC20(rewardTokenAddress);
        return token.balanceOf(address(this));
    }

    /**
   * @dev Returns the address of the NFT contract on which
   * @dev the tickets for the current draw were minted.
   * 
   * @notice If you want to participate in the next draw
   * @notice you need to buy a ticket with the contract address
   * @notice that matches the address that this function
   * @notice returns.
   * 
   * @notice If you are getting a null address, please wait
   * @notice until we are done setting up a new address with
   * @notice new tickets.
   */
    function getNftAddress() public view returns (address) {
        return nftAddress;
    }

    /**
   * @dev Returns the address of the ERC20 token which
   * @dev is the current draw currency.
   * 
   * @notice If you are getting a null address, please wait
   * @notice until we are done setting up a new address with
   * @notice new tickets and tokens (tokens address in the normal
   * @notice situation will not be changed from WETH address).
    */
    function getRewardTokenAddress() public view returns (address) {
        return rewardTokenAddress;
    }

    /**
   * @dev Returns the value in seconds when the recent draw was played.
   */
    function getDrawDate() public view returns (uint256) {
        return _drawDate;
    }

    /**
   * @dev Returns true if there was a failure during the draw.
   */
    function getDrawFailedStatus() public view returns (bool) {
        return isDrawFailed;
    }

}