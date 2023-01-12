// SPDX-License-Identifier: MIT

/// @custom:created-with-openzeppelin-wizard https://wizard.openzeppelin.com


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

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./DateTime.sol";
import "./Base64.sol";

/**
 * @dev Custom errors.
 */
error NoAnOwner();
error NotALottery();

contract CryptotronTicket is ERC721, ERC721Enumerable, ERC721Burnable {

    enum lotteryState {
        PENDING,
        OPEN,
        PROCESSING,
        OVER,
        REFUNDED
    }

    /**
    * @dev Type declarations.
    */
    using Counters for Counters.Counter;
    using Strings for uint256;
    Counters.Counter private _tokenIdCounter;
    lotteryState private s_lotteryState;
    address payable private ownerAddress;
    address private lotteryAddress = address(payable(0x0));
    uint256 private winnerId;
    uint256 private drawDate;
    uint256 private immutable i_tokensCount = 25;
    bool private isLotteryOver = false;

    /**
    * @dev events.
    */
    event SetDrawDate(address indexed operator);
    event SetStatusRefunded(address indexed operator);
    event SetStatusProcessing(address indexed operator);
    event SetStatusOpen(address indexed operator);
    event SetStatusOver(address indexed operator);
    event WinnerIdSet(address indexed operator);
    event LotteryAddressSet(address indexed operator);
    event Minted(address indexed recipient);

    /**
    * @dev Modifiers.
    */
    modifier onlyOwner() {
        if (msg.sender != ownerAddress) {
            revert NoAnOwner();
        }
        _;
    }

    modifier onlyLottery() {
        if (msg.sender != lotteryAddress) {
            revert NotALottery();
        }
        _;
    }

    /**
    * @dev {ERC721} default constructor.
    */
    constructor() ERC721("CryptoTronTicket", "CTT") {
        ownerAddress = payable(msg.sender);
        s_lotteryState = lotteryState.PENDING;
    }

    /**
    * @dev sets the beuty-looking date in "Traits".
    */
    function setDrawDate(uint256 minDrawDate) external onlyLottery {
        drawDate = minDrawDate;
        emit SetDrawDate(msg.sender);
    }

    /**
    * @dev changes the status of every ticket (next to the name) to mark them as invalid (aka Refunded).
    */
    function setStateRefunded() external onlyLottery {
        s_lotteryState = lotteryState.REFUNDED;
        emit SetStatusRefunded(msg.sender);
    }

    /**
    * @dev one of the initial conditions of the draw.
    */
    function setStateOpen() external onlyLottery {
        s_lotteryState = lotteryState.OPEN;
        emit SetStatusOpen(msg.sender);
    }

    /**
    * @dev displays the moment the winner is calculated.
    */
    function setStateProcessing() external onlyLottery {
        s_lotteryState = lotteryState.PROCESSING;
        emit SetStatusProcessing(msg.sender);
    }

    /**
    * @dev displays the moment the winner is picked and the current draw is over.
    */
    function setStateOver() external onlyLottery {
        s_lotteryState = lotteryState.OVER;
        emit SetStatusOver(msg.sender);
    }

    /**
    * @dev awaits for passing the winning tokenId from lottery contract.
    */
    function setWinnerId(uint256 _winnerId) external onlyLottery {
        winnerId = _winnerId;
        emit WinnerIdSet(msg.sender);
    }

    /**
    * @dev Function that's being used by lottery contract to get the amount of participating tickets.
    */
    function getSoldTicketsCount() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

    /**
    * @dev  Safely transfers the ownership of a given token ID to another address If the target 
    * address is a contract, it must implement {IERC721Receiver.onERC721Received}, which is 
    * called upon a safe transfer. Requires the msg.sender to be the owner, approved, or operator.
    */
    function safeMint(address to) public onlyOwner {
        require(_tokenIdCounter.current() < i_tokensCount, "Maximum NFT count is minted");
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        emit Minted(to);
    }

    /**
    * @dev used for setting lottery contract address.
    */
    function setLotteryAddress(address _lotteryAddress) public onlyOwner {
        lotteryAddress = payable(_lotteryAddress);
    }

    function getImage(uint256 tokenId) public view returns (string memory) {
        if (tokenId == winnerId) {
            return "https://ipfs.io/ipfs/QmRQYhTUqKez8BdM4UCBZUTntDxRXD9RVxdXb8Czb32mHm?filename=winnerDraw1.png";
        } else {
            return "https://ipfs.io/ipfs/QmeDt5otWVSh6u7vTV7odmXB88Ytyd1LWjNjCTAoeLyCd4?filename=participantDraw1.png";
        }
    }

    /**
    * @dev returns the beauty-looking date of the draw.
    */
    function getDrawDate() public view returns (string memory) {
        if (drawDate == 0){
            return "Not Set Yet";
        }

        (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(drawDate);
        return string(abi.encodePacked(Strings.toString(year), '.', month < uint256(10) ? "0" : "", Strings.toString(month), '.', day < uint256(10) ? "0" : "", Strings.toString(day)));
    }

    /**
    * @dev use it to see the lottery address.
    */
    function getLotteryContractAddress() public view returns (string memory){
        if (lotteryAddress == address(0x0)) {
            return "Not assigned";
        } else {
            return Strings.toHexString(uint160(lotteryAddress), 20);
        }
    }

    /**
    * @dev Returns true if this contract implements the interface defined by interfaceId.
    */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
    * @dev returns the status (in the name tag) of the ticket (and lottery).
    */
    function getLotteryStatus(uint256 tokenId) public view returns (string memory) {
        if (s_lotteryState == lotteryState.PENDING) {
            return "Inactive";
        } else if (s_lotteryState == lotteryState.OPEN) {
            return "Active";
        } else if (s_lotteryState == lotteryState.PROCESSING) {
            return "Drawing";
        } else if (s_lotteryState == lotteryState.OVER) {
            if (tokenId == winnerId) {
                return "Won";
            } else {
                return "Drawn";
            }
        } else if (s_lotteryState == lotteryState.REFUNDED) {
            return "Refunded";
        }
    }

    /**
    * @dev sets the trait type for indicating the status of the draw.
    */
    function getDrawState(uint256 tokenId) public view returns (string memory) {
        if (s_lotteryState == lotteryState.PENDING) {
            return "Inactive";
        } else if (s_lotteryState == lotteryState.OPEN) {
            return "Coming Soon";
        } else if (s_lotteryState == lotteryState.PROCESSING) {
            return "Processing";
        } else if (s_lotteryState == lotteryState.OVER) {
            if (tokenId == winnerId) {
                return "Won";
            } else {
                return "Didn't win";
            }
        } else if (s_lotteryState == lotteryState.REFUNDED) {
            return "Refunded";
        }
    }

    /**
    * @dev mixed on-chain and off-xhain metadata.
    */
    function tokenURI(uint256 tokenId) override(ERC721) public view returns (string memory) {
        require(tokenId != 0, "Incorrect token id");
        require(tokenId <= _tokenIdCounter.current(), "Ticket does't exist");

        string memory json = Base64.encode(
            bytes(string(
                abi.encodePacked(
                    '{',
                    '"name": "CryptoTron Ticket #', Strings.toString(tokenId), ' ' , unicode"—" , ' ', getLotteryStatus(tokenId) ,'",',
                    '"image": "', getImage(tokenId), '",',
                    '"attributes": [{"trait_type": "Chance", "value": "1 to 25" },',
                    '{"trait_type": "Prize", "value": "0.1 ETH" },',
                    '{"trait_type": "Project", "value": "Cryptotron" },',
                    '{"trait_type": "Ticket Status", "value": "', getDrawState(tokenId), '" },',
                    '{"trait_type": "Draw Date", "value": "', getDrawDate(), '" }',
                    '],'
                    '"description": ',
                        '"Cryptotron lottery is a fully smart-contract-based raffle that uses Chainlink oracle network for provably fair random numbers',
                        '\\n','\\n',
                        'Hold this ticket at the draw date and have a chance to win the prize',
                        '\\n','\\n',
                        'When the lottery is active, no one can modify or interrupt the process',
                        '\\n',
                        'You don', unicode"’" ,'t need to trust us because the lottery is protected by the math',
                        '\\n','\\n',
                        'Lottery contract address - ', getLotteryContractAddress(), ' (Polygon)',
                        '\\n','\\n',
                        'Image generated by DALL', unicode"·" ,'E"'
                    '}'
                )
            )));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    /**
    * Hook, which is being used for implementing IERC721Receiver.
    */
    function _beforeTokenTransfer(
        address from, 
        address to, 
        uint256 tokenId, 
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) 
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

}