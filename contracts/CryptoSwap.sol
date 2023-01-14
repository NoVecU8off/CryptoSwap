// SPDX-License-Identifier: Apache-2.0

/*
                        ::                                                      
                     .JG&#~                                                     
                      ?@@@&?                                                    
                       ~#@@@5                                                   
                        :G@@@G!!!!!!!!!!!!!!!!!!!!!!:                           
                          Y@@@@@@@@@@@@@@@@@@@@@@@@@#!                          
                           75YYYYYYYYYYYYYYYYYYYY5&@@@J                         
                                                  ^B@@@5.                       
                                                   .P@@@B^                      
                     ~~.                             J@@@#!                     
                    ?@@#Y       .:            :.      !&@@@?                    
                  .5@@@B~      :B&!          !&B:      ^B@@@5.                  
                 :B@@@P.      ~#@@@J        J@@@#~      .P@@@B:                 
                !#@@&J       ?@@@@@@P.    .P@@@@@@?       J&@@#!                
               ^&@@@5       !@@@@@@@@Y    Y@@@@@@@@!       5@@@&^               
                !#@@&J       ~B@@@@&?      ?&@@@@B~       J&@@#!                
                 :G@@@P.       ?&@5:        :5@&?       .P@@@G:                 
                  .5@@@B^       ^!            !^       ^B@@@5.                  
                    ?@@@&7                            7&@@@?                    
                     !#@@@J                          J@@@#!                     
                      :B@@@P.                      .P@@@B:                      
                       .5@@@B^                    ^B@@@5.                       
                         ?@@@&55555555555555555555&@@@?                         
                          !#@@@@@@@@@@@@@@@@@@@@@@@@#!                          
*/

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

error NotAnOwner();
error NullAddress();
error TokenDoesNotExist();

contract CryptoSwap {

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
        bool agreementReached;
        bool swapSucceed;
    }

    // struct Couneroffer {
    //     address respondentAddress;
    //     address responderTokenAddress;
    //     uint256 responderTokenId;
    // }

    mapping(uint => DirectOffer) public directOffers;
    mapping(uint => CommonOffer) public commonOffers;
    mapping(address => uint[]) private directOffersByAddress;
    mapping(address => uint[]) private commonOffersByAddress;

    ERC721 private token;
    ERC721 private tokenA;
    ERC721 private tokenB;

    Counters.Counter private directOfferIdCounter;
    Counters.Counter private commonOfferIdCounter;
    Counters.Counter private transactionIdCounter;

    uint256 directOfferId;
    uint256 commonOfferId;
    uint256 transactionId;

    event NewDirectOffer(address indexed initiator, DirectOffer directOffer);
    event NewCommonOffer(address indexed initiator, CommonOffer commonOffer);
    event OfferTermsAccepted(address indexed respondent);
    event OfferTermsNotAccepted(address indexed respondent);
    event InitiatorTokenTransfered(uint256 indexed transactionId);
    event RecipientTokenTransfered(uint256 indexed transactionId);

    function createDirectOffer(
        address _initiatorTokenAddress,
        uint256 _initiatorTokenId,
        address _recipientAddress,
        address _recipientTokenAddress,
        uint256 _recipientTokenId
    )
        public
    {

        token = ERC721(_initiatorTokenAddress);

        if (msg.sender != token.ownerOf(_initiatorTokenId)) {
            revert();
        } else if (_exists(_initiatorTokenId, _initiatorTokenAddress) != true) {
            revert();
        }

        token = ERC721(_recipientTokenAddress);

        if (_recipientAddress == address(0)) {
            revert();
        } else if (_recipientAddress != token.ownerOf(_recipientTokenId)) {
            revert();
        } else if (_exists(_recipientTokenId, _recipientTokenAddress) != true) {
            revert();
        }

        directOfferIdCounter.increment();
        directOfferId = directOfferIdCounter.current();

        directOffers[directOfferId] = DirectOffer(
            msg.sender,
            _initiatorTokenAddress,
            _initiatorTokenId,
            _recipientAddress,
            _recipientTokenAddress,
            _recipientTokenId,
            false,
            false
        );

        directOffersByAddress[msg.sender].push(directOfferId);

        emit NewDirectOffer(msg.sender, directOffers[directOfferId]);

    }

    function createCommonOffer(address _initiatorTokenAddress, uint256 _initiatorTokenId) public {

        token = ERC721(_initiatorTokenAddress);

        if (msg.sender != token.ownerOf(_initiatorTokenId)) {
            revert();
        } else if (_exists(_initiatorTokenId, _initiatorTokenAddress) != true) {
            revert();
        }

        commonOfferIdCounter.increment();
        commonOfferId = commonOfferIdCounter.current();

        commonOffers[commonOfferId] = CommonOffer(
            msg.sender,
            _initiatorTokenAddress,
            _initiatorTokenId,
            false,
            false
        );

        commonOffersByAddress[msg.sender].push(commonOfferId);

        emit NewCommonOffer(msg.sender, commonOffers[commonOfferId]);

    }

    function acceptDirectOffer(uint256 _directOfferId, bool _yourResponse) public {

        if (msg.sender != directOffers[_directOfferId].recipientAddress) {
            revert();
        }

        directOffers[_directOfferId].termsAcceptedByRecipient = _yourResponse;

        if (_yourResponse == true) {
            emit OfferTermsAccepted(msg.sender);
        } else {
            emit OfferTermsNotAccepted(msg.sender);
        }

    }

    function executeDirectOffer(uint256 _directOfferId) public {

        if (msg.sender != directOffers[_directOfferId].recipientAddress) {
            revert();
        } else if (directOffers[_directOfferId].termsAcceptedByRecipient != true) {
            revert();
        }

        tokenA = ERC721(directOffers[_directOfferId].initiatorTokenAddress);
        tokenB = ERC721(directOffers[_directOfferId].recipientTokenAddress);

        if (tokenA.getApproved(directOffers[_directOfferId].initiatorTokenId) != address(this)) {
            revert();
        } else if (tokenB.getApproved(directOffers[_directOfferId].recipientTokenId) != address(this)) {
            revert();
        } else {
            tokenA.safeTransferFrom(
                directOffers[_directOfferId].initiatorAddress,
                directOffers[_directOfferId].recipientAddress,
                directOffers[_directOfferId].initiatorTokenId
            );

            transactionIdCounter.increment();
            transactionId = transactionIdCounter.current();

            emit InitiatorTokenTransfered(transactionId);

            tokenB.safeTransferFrom(
                directOffers[_directOfferId].recipientAddress,
                directOffers[_directOfferId].initiatorAddress,
                directOffers[_directOfferId].initiatorTokenId
            );

            emit RecipientTokenTransfered(transactionId);

            directOffers[_directOfferId].swapSucceed = true;
        }

    }

    // function createResponseOffer(
    //     uint256 _commonOfferId,
    //     address _responderTokenAddress,
    //     uint256 _responderTokenId
    // )
    // public
    // {

    //     token = ERC721(_responderTokenAddress);

    //     if (msg.sender != token.ownerOf(_responderTokenId)) {
    //         revert();
    //     } else if (_exists(_responderTokenId, _responderTokenAddress) != true) {
    //         revert();
    //     }

        

    // }

    function getDirectOffersIdsByAddress(address _initiatorAddress) public view returns(uint[] memory) {
        return directOffersByAddress[_initiatorAddress];
    }

    function getCommonOffersIdsByAddress(address _initiatorAddress) public view returns(uint[] memory) {
        return commonOffersByAddress[_initiatorAddress];
    }

    function _exists(uint256 _tokenId, address _tokenAddress) internal virtual returns (bool) {
        token = ERC721(_tokenAddress);
        return token.ownerOf(_tokenId) != address(0);
    }

}