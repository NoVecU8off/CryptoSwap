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

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "hardhat/console.sol";
import "./CryptoTronTicket.sol";

/**
* @dev interface of NFT smart contract, that provides functionality 
* @dev for enterCryptotron function.
*/
interface CryptoTicketInterface {
    function ownerOf(uint256 tokenId) external view returns (address);
    function sold() external view returns (uint256 ammount);
}

/**
* @dev Errors.
*/
error Cryptotron__UpkeepFailed(uint256 currentBalance, uint256 numPlayers, uint256 cryptotronState);
error Cryptotron__TransferFailed();
error Cryptotron__StateFailed();
error Cryptotron__FailureDetected();
error Cryptotron__FailureUndetected();
error Cryptotron__OwnerRightsFailure();
error Cryptotron__ZeroingFailure();
error Cryptotron__EmergencyRefundFailure();

/**@title CryptoGamble project
* @author Andrey Novikov
*/
contract CryptoTron is VRFConsumerBaseV2, AutomationCompatibleInterface {

    /**
   * @dev Cryptotron state diclaration.
   */
    enum cryptotronState {
        OPEN,
        CALCULATING
    }

    /**
   * @dev Variables.
   */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    cryptotronState private s_cryptotronState;
    bytes32 private immutable i_gasLane;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    uint256 private refundAmmount;
    uint256 private tokenId;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 4;
    address payable[] private s_players;
    address payable[] s_funders;
    address payable[] s_refunders;
    address[] private s_allWinners;
    address[] internal deprecatedContracts;
    address private currentContract;
    address private s_recentWinner;
    address payable public owner;
    address private nullAddress = address(0x0);
    bool private failure = false;

    /**
   * @dev Events for the future dev.
   */
    event RequestedCryptotronWinner(uint256 indexed requestId);
    event CryptotronEnter(address indexed player);
    event WinnerPicked(address indexed winner);
    event AddressChanged(address indexed newAddress);
    event EmergencyRefund(address indexed refunder);
    event FailureWasReset(uint256 indexed timesReset);
    event NewFunder(address indexed funder);

    /**
   * @dev Replacement for the reqire(msg.sender == owner);
   */
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Cryptotron__OwnerRightsFailure();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(currentContract == nullAddress);
   */
    modifier contractRestriction() {
        if (currentContract != nullAddress) {
            revert Cryptotron__ZeroingFailure();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(failure == false);
   */
    modifier checkFailure() {
        if (failure != false) {
            revert Cryptotron__FailureDetected();
        }
        _;
    }

    /**
   * @dev Replacement for the reqire(failure == true);
   */
    modifier approveFailure() {
        if (failure != true) {
            revert Cryptotron__FailureUndetected();
        }
        _;
    }

    /**
   * @dev Constructor with the arguments for the VRFConsumerBaseV2
   */
    constructor(
        bytes32 gasLane,
        uint256 interval,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_cryptotronState = cryptotronState.OPEN;
        s_lastTimeStamp = block.timestamp;
        owner = payable(msg.sender);
        currentContract = nullAddress;
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
    ) external override checkFailure {
        enterCryptotron();
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            failure = true;
            revert Cryptotron__UpkeepFailed(
                address(this).balance,
                s_players.length,
                uint256(s_cryptotronState)
            );
        }
        s_cryptotronState = cryptotronState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedCryptotronWinner(requestId);
    }

    /**
   * @dev Checker function. When Chainlink Automation calls performUpkeep
   * @dev function it calls this checker function and waits for it to return
   * @dev boolean true so performUpkeep can proceed and make request to ChainlinkVRF. 
   * @dev Params checked: current state, passed time, players ammount, balance of the contract.
   */
    function checkUpkeep(
        bytes memory
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        bool isOpen = cryptotronState.OPEN == s_cryptotronState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > /*7 days, dev = */ i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    /**
   * @dev This function is for changing the contract of Cryptotron Tickets
   * @dev that becomes reachable only after recent address becomes nullAddress
   * @dev (which means that the last draw is over). Also it's failure restrickted
   * @dev (bool failure == false) and can be called only by owner.
   */
    function changeAddress(address newAddress) public onlyOwner checkFailure contractRestriction {
        currentContract = newAddress;
        emit AddressChanged(newAddress);
    }

    /**
   * @dev This fuction is for refunding purchased tickets to Cryptotron
   * @dev members during an emergency (bool failure = true).
   * @dev Function is public, so everyone can call it.
   * @dev Keeps track of callers of this function.
   */
    function emergencyRefund() public approveFailure {
        s_refunders.push(payable(msg.sender));
        currentContract = nullAddress;
        if (address(this).balance == 0) {
            revert Cryptotron__EmergencyRefundFailure();
        } else {
            refundAmmount = (address(this).balance / s_players.length);
            for (uint i = 0; i < s_players.length; i++) {
                s_players[i].transfer(refundAmmount);
            }
        }
        emit EmergencyRefund(msg.sender);
    }

    /**
   * @dev This function will be used to reset falure state of the Cryptotron
   * @dev only after required tests of failed version.
   *  
   * @notice Maybe this function will never be touched.
   */
    function resetFailure(uint256 timesReset) public onlyOwner {
        timesReset += timesReset;
        failure = false;
        emit FailureWasReset(timesReset);
    }

    /**
   * @dev This function was made just for funding the Cryptotron.
   *
   * @notice You can increase lottery winnings. But it is not changing
   * @notice youre chances for the win. We are asking you to enter your
   * @notice address as funderAddress just to store it for future. :)
   *
   * @notice Do not use this function to enter the Cryptotron.
   */
    function fundCryptotron() public payable checkFailure {
        s_funders.push(payable(msg.sender));
        emit NewFunder(msg.sender);
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
    ) internal override checkFailure {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_allWinners.push(recentWinner);
        deprecatedContracts.push(currentContract);
        currentContract = nullAddress;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            failure = true;
            revert Cryptotron__TransferFailed();
        }
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_cryptotronState = cryptotronState.OPEN;
        emit WinnerPicked(recentWinner);
    }

    /**
   * @dev enterCryptotron is the internal function that is getting kicked off
   * @dev by performUpkeep and sets the cryptotron players aka owners of each
   * @dev ticket (owner of each tokenId).
   * 
   * @notice Number of players determaned by the quantity of
   * @notice tokenIds which were minted with the actual NFT contract (you allways
   * @notice can check the ammount of tickets, prices ect. by calling currentContract
   * @notice function on Etherscan. Path: Etherscan -> address (this) ->
   * @notice -> Contract -> Read Contract -> currentContract -> Nft contract ->
   * @notice -> Read Contract)
   */
    function enterCryptotron() internal checkFailure {
        if (s_cryptotronState != cryptotronState.OPEN) {
            revert Cryptotron__StateFailed();
        }
        CryptoTicketInterface cti = CryptoTicketInterface(currentContract);
        for (tokenId = 0; tokenId < cti.sold(); tokenId++) {
            s_players.push(payable(cti.ownerOf(tokenId)));
            emit CryptotronEnter(cti.ownerOf(tokenId));
        }
    }   

    /**
   * @dev Returns the balance of the Cryptotron contract
   * 
   * @notice This funds are the "Jackpot" of the Cryptotron
   */
    function getCryptotronBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
   * @dev Returns the address of the NFT contract on which
   * @dev the tickets for the current draw were minted
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
    function getCurrentContract() public view returns (address) {
        return currentContract;
    }

    /**
   * @dev Returns an array of previous draws.
   */
    function getDeprecatedContracts() public view returns (address[] memory) {
        return deprecatedContracts;
    }

    /**
   * @dev Returns enum type value (0 - Cryptotron is open, 1 - Cryptotron is calculating).
   */
    function getCryptotronState() public view returns (cryptotronState) {
        return s_cryptotronState;
    }

    /**
   * @dev Returns ammount of words (aka numbers) requested by performUpkeep.
   */
    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    /**
   * @dev Returns how many blocks we'd like the oracle to wait before responding to
   * @dev the request.
   */
    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    /**
   * @dev Returns previous winner.
   */
    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    /**
   * @dev Returns the value in seconds when the recent draw was played.
   */
    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    /**
   * @dev Returns the interval as a constructor argument for VRF.
   */
    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    /**
   * @dev Returns an array of all previous winners.
   */
    function getAllWinners() public view returns (address[] memory) {
        return s_allWinners;
    }

    /**
   * @dev Returns true if there was a failure during the draw.
   */
    function isFailed() public view returns (bool) {
        return failure;
    }

}