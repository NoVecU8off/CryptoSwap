// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

error NotAnOwner();
error NullAddress();
error TokenDoesNotExist();
error NotRecipient();
error TermsNotAccepted();
error TokenNotApproved();
error YouAreNotInitiator();
error OfferDoesNotExist();
error YouAreNotCounter();

contract swap {

    using Counters for Counters.Counter;

    struct DirectOffer {
        address initiatorAddress;
        address initiatorTokenAddress;
        uint256 initiatorTokenId;
        address recipientAddress;
        address recipientTokenAddress;
        uint256 recipientTokenId;
        bool termsAcceptedByRecipient;
        bool swapSucceed;
    }

    struct CommonOffer {
        address initiatorAddress;
        address initiatorTokenAddress;
        uint256 initiatorTokenId;
        uint256[] counterOfferIds;
        bool agreementReached;
        bool swapSucceed;
    }

    struct CounterOffer {
        address counterAddress;
        address counterTokenAddress;
        uint256 counterTokenId;
    }

    mapping(uint => DirectOffer) public directOfferById;
    mapping(uint => CommonOffer) public commonOfferById;
    mapping(uint => CounterOffer) public counterOfferById;
    mapping(address => uint[]) private directOfferIDsByAddress;
    mapping(address => uint[]) private directOfferIDsToAddress;
    mapping(address => uint[]) private commonOfferIDsByAddress;
    mapping(uint => uint[]) private counterOfferIDsToCommonOffer;

    Counters.Counter private directOfferIdCounter;
    Counters.Counter private commonOfferIdCounter;
    Counters.Counter private transferIdCounter;
    Counters.Counter private counterOfferIdCounter;

    uint256 private directOfferId;
    uint256 private commonOfferId;
    uint256 private counterOfferId;
    uint256 private transferId;

    event NewDirectOfferBy(address indexed initiator, uint256 indexed offerId);
    event NewCommonOfferBy(address indexed initiator, uint256 indexed offerId);
    event NewCounterOfferBy(address indexed respondent, uint256 indexed offerId);
    event OfferTermsAccepted(address indexed respondent, uint256 indexed offerId);
    event OfferTermsNotAccepted(address indexed respondent, uint256 indexed offerId);
    event InitiatorTokenTransfered(uint256 indexed transferId, address indexed from, address indexed to);
    event RecipientTokenTransfered(uint256 indexed transferId, address indexed from, address indexed to);

    function createDirectOffer(
        address _initiatorTokenAddress,
        uint256 _initiatorTokenId,
        address _recipientAddress,
        address _recipientTokenAddress,
        uint256 _recipientTokenId
    )
        public
    {
        
        ERC721 token;

        token = ERC721(_initiatorTokenAddress);

        if (msg.sender != token.ownerOf(_initiatorTokenId)) {
            revert NotAnOwner();
        } else if (_exists(_initiatorTokenId, _initiatorTokenAddress) != true) {
            revert TokenDoesNotExist();
        }

        token = ERC721(_recipientTokenAddress);

        if (_recipientAddress == address(0)) {
            revert NullAddress();
        } else if (_recipientAddress != token.ownerOf(_recipientTokenId)) {
            revert NotAnOwner();
        } else if (_exists(_recipientTokenId, _recipientTokenAddress) != true) {
            revert TokenDoesNotExist();
        }

        directOfferIdCounter.increment();
        directOfferId = directOfferIdCounter.current();

        directOfferById[directOfferId] = DirectOffer(
            msg.sender,
            _initiatorTokenAddress,
            _initiatorTokenId,
            _recipientAddress,
            _recipientTokenAddress,
            _recipientTokenId,
            false,
            false
        );

        directOfferIDsByAddress[msg.sender].push(directOfferId);
        directOfferIDsToAddress[_recipientAddress].push(directOfferId);

        emit NewDirectOfferBy(msg.sender, directOfferId);

    }

    function respondToDirectOffer(uint256 _directOfferId, bool _yourResponse) public {

        if (msg.sender != directOfferById[_directOfferId].recipientAddress) {
            revert NotRecipient();
        } else if (_checkDirectOfferExists(_directOfferId) != true) {
            revert OfferDoesNotExist();
        }

        directOfferById[_directOfferId].termsAcceptedByRecipient = _yourResponse;

        if (_yourResponse == true) {
            emit OfferTermsAccepted(msg.sender, _directOfferId);
        } else {
            emit OfferTermsNotAccepted(msg.sender, _directOfferId);
        }

    }

    function executeDirectOffer(uint256 _directOfferId) public {

        if (msg.sender != directOfferById[_directOfferId].recipientAddress) {
            revert NotRecipient();
        } else if (directOfferById[_directOfferId].termsAcceptedByRecipient != true) {
            revert TermsNotAccepted();
        }

        ERC721 tokenA;
        ERC721 tokenB;

        tokenA = ERC721(directOfferById[_directOfferId].initiatorTokenAddress);
        tokenB = ERC721(directOfferById[_directOfferId].recipientTokenAddress);

        if (tokenA.getApproved(directOfferById[_directOfferId].initiatorTokenId) != address(this)) {
            revert TokenNotApproved();
        } else if (tokenB.getApproved(directOfferById[_directOfferId].recipientTokenId) != address(this)) {
            revert TokenNotApproved();
        } else {
            tokenA.safeTransferFrom(
                directOfferById[_directOfferId].initiatorAddress,
                directOfferById[_directOfferId].recipientAddress,
                directOfferById[_directOfferId].initiatorTokenId
            );

            transferIdCounter.increment();
            transferId = transferIdCounter.current();

            emit InitiatorTokenTransfered(
                transferId,
                directOfferById[_directOfferId].initiatorAddress,
                directOfferById[_directOfferId].recipientAddress
            );

            tokenB.safeTransferFrom(
                directOfferById[_directOfferId].recipientAddress,
                directOfferById[_directOfferId].initiatorAddress,
                directOfferById[_directOfferId].initiatorTokenId
            );

            transferIdCounter.increment();
            transferId = transferIdCounter.current();

            emit RecipientTokenTransfered(
                transferId,
                directOfferById[_directOfferId].recipientAddress,
                directOfferById[_directOfferId].initiatorAddress
            );

            directOfferById[_directOfferId].swapSucceed = true;
        }

    }

    function createCommonOffer(address _initiatorTokenAddress, uint256 _initiatorTokenId) public {

        ERC721 token;

        token = ERC721(_initiatorTokenAddress);

        if (msg.sender != token.ownerOf(_initiatorTokenId)) {
            revert NotAnOwner();
        } else if (_exists(_initiatorTokenId, _initiatorTokenAddress) != true) {
            revert TokenDoesNotExist();
        }

        uint256[] memory counterOfferIds = new uint256[](0);

        commonOfferIdCounter.increment();
        commonOfferId = commonOfferIdCounter.current();

        commonOfferById[commonOfferId] = CommonOffer(
            msg.sender,
            _initiatorTokenAddress,
            _initiatorTokenId,
            counterOfferIds,
            false,
            false
        );

        commonOfferIDsByAddress[msg.sender].push(commonOfferId);

        emit NewCommonOfferBy(msg.sender, commonOfferId);

    }

    function createCounterOffer(
        uint256 _commonOfferId,
        address _counterTokenAddress,
        uint256 _counterTokenId
    )
    public
    {

        ERC721 token;

        token = ERC721(_counterTokenAddress);

        if (msg.sender != token.ownerOf(_counterTokenId)) {
            revert NotAnOwner();
        } else if (_exists(_counterTokenId, _counterTokenAddress) != true) {
            revert TokenDoesNotExist();
        } else if (_checkCommonOfferExists(_commonOfferId) != true) {
            revert OfferDoesNotExist();
        }

        counterOfferIdCounter.increment();
        counterOfferId = counterOfferIdCounter.current();
        commonOfferById[_commonOfferId].counterOfferIds.push(counterOfferId);

        counterOfferById[counterOfferId].counterAddress = msg.sender;
        counterOfferById[counterOfferId].counterTokenAddress = _counterTokenAddress;
        counterOfferById[counterOfferId].counterTokenId = _counterTokenId;

        counterOfferIDsToCommonOffer[_commonOfferId].push(counterOfferId);

        emit NewCounterOfferBy(msg.sender, counterOfferId);

    }

    function respondToCounterOffer(uint256 _yourCommonOfferId, uint256 _counterOfferId, bool _yourResponse) public {

        if (msg.sender != commonOfferById[_yourCommonOfferId].initiatorAddress) {
            revert YouAreNotInitiator();
        } else if ( _checkCounterOfferExists(_counterOfferId, _yourCommonOfferId) != true) {
            revert OfferDoesNotExist();
        } else if (_yourResponse == true) {
            commonOfferById[_yourCommonOfferId].agreementReached = true;
        } else {
            commonOfferById[_yourCommonOfferId].agreementReached = false;
        }

    }

    function executeCommonOffer(uint256 _commonOfferId, uint256 _counterOfferId) public {

        if (msg.sender != counterOfferById[_counterOfferId].counterAddress) {
            revert YouAreNotCounter();
        } else if (commonOfferById[_commonOfferId].agreementReached != true) {
            revert TermsNotAccepted();
        }

        ERC721 tokenA;
        ERC721 tokenB;

        tokenA = ERC721(commonOfferById[_commonOfferId].initiatorTokenAddress);
        tokenB = ERC721(counterOfferById[_counterOfferId].counterTokenAddress);

        if (tokenA.getApproved(commonOfferById[_commonOfferId].initiatorTokenId) != address(this)) {
            revert TokenNotApproved();
        } else if (tokenB.getApproved(counterOfferById[_counterOfferId].counterTokenId) != address(this)) {
            revert TokenNotApproved();
        } else {
            tokenA.safeTransferFrom(
                commonOfferById[_commonOfferId].initiatorAddress,
                counterOfferById[_counterOfferId].counterAddress,
                commonOfferById[_commonOfferId].initiatorTokenId
            );

            transferIdCounter.increment();
            transferId = transferIdCounter.current();

            emit InitiatorTokenTransfered(
                transferId,
                commonOfferById[_commonOfferId].initiatorAddress,
                counterOfferById[_counterOfferId].counterAddress
            );

            tokenB.safeTransferFrom(
                counterOfferById[_counterOfferId].counterAddress,
                commonOfferById[_commonOfferId].initiatorAddress,
                counterOfferById[_counterOfferId].counterTokenId
            );

            emit RecipientTokenTransfered(
                transferId,
                counterOfferById[_counterOfferId].counterAddress,
                commonOfferById[_commonOfferId].initiatorAddress
            );

            commonOfferById[_commonOfferId].swapSucceed = true;
        }

    }

    function getDirectOffersIDsByAddress(address _initiatorAddress) public view returns (uint[] memory) {
        return directOfferIDsByAddress[_initiatorAddress];
    }

    function getDirectOffersIDsToAddress(address _recipientAddress) public view returns (uint[] memory) {
        return directOfferIDsToAddress[_recipientAddress];
    }

    function getCommonOffersIDsByAddress(address _initiatorAddress) public view returns (uint[] memory) {
        return commonOfferIDsByAddress[_initiatorAddress];
    }

    function getCounterOfferIDsToCommonOfferID(uint256 _commonOfferId) public view returns(uint[] memory) {
        return counterOfferIDsToCommonOffer[_commonOfferId];
    }

    function _exists(uint256 _tokenId, address _tokenAddress) internal virtual returns (bool) {
        ERC721 token;
        token = ERC721(_tokenAddress);
        return token.ownerOf(_tokenId) != address(0);
    }

    function _checkDirectOfferExists(uint256 _directOfferId) internal view returns (bool) {
        return directOfferById[_directOfferId].initiatorAddress != address(0);
    }

    function _checkCommonOfferExists(uint256 _commonOfferId) internal view returns (bool) {
        return commonOfferById[_commonOfferId].initiatorAddress != address(0);
    }

    function _checkCounterOfferExists(uint256 _counterOfferId, uint256 _commonOfferId) internal view returns (bool) {
        for (uint256 i = 0; i < commonOfferById[_commonOfferId].counterOfferIds.length; i++) {
            if (commonOfferById[_commonOfferId].counterOfferIds[i] == _counterOfferId) {
                return true;
            } 
        }
        return false;
    }

}