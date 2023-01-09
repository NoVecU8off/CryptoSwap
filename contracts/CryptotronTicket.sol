// SPDX-License-Identifier: MIT

/// @custom:created-with-openzeppelin-wizard https://wizard.openzeppelin.com

/// @custom:security-contact andrewnovikoff@outlook.com

/*_________________________________________CRYPTOTRON_________________________________________*/

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./DateTime.sol";
import "./Base64.sol";

/**
 * @dev Custom errors
 */
error NoAnOwnerError();
error NotALotteryError();

contract CryptotronTicket is ERC721, ERC721Enumerable, ERC721Burnable {
    enum lotteryState {
        OPEN,
        PROCESSING,
        OVER
    }

    /**
   * @dev Type declarations
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
   * @dev Modifiers
   */
    modifier onlyOwner() {
        if (msg.sender != ownerAddress) {
            revert NoAnOwnerError();
        }
        _;
    }

    modifier onlyLottery() {
        if (msg.sender != lotteryAddress) {
            revert NotALotteryError();
        }
        _;
    }

    /**
   * @dev {ERC721} default constructor
   */
    constructor() ERC721("CryptotronTicket", "CTT") {
        ownerAddress = payable(msg.sender);
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
    }

    function getDrawDate() public view returns (string memory) {
        if (drawDate == 0){
            return "Not Set";
        }

        (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(drawDate);
        return string(abi.encodePacked(Strings.toString(year), '.', month < uint256(10) ? "0" : "", Strings.toString(month), '.', day < uint256(10) ? "0" : "", Strings.toString(day)));
    }

    function getLotteryContractAddress() public view returns (string memory){
        if (lotteryAddress == address(0x0)) {
            return "Not assigned";
        } else {
            return Strings.toHexString(uint160(lotteryAddress), 20);
        }
    }

    function getLotteryStatus() public view returns (string memory) {
        if (s_lotteryState == lotteryState.OPEN) {
            return "Active";
        } else if (s_lotteryState == lotteryState.PROCESSING) {
            return "Drawing";
        } else if (s_lotteryState == lotteryState.OVER) {
            return "Ended";
        }
    }

    function getDrawState(uint256 tokenId) public view returns (string memory) {
        if (s_lotteryState == lotteryState.OVER) {
            if (tokenId == winnerId) {
                return "Won";
            } else {
                return "Didn't win";
            }
        } else if (s_lotteryState == lotteryState.PROCESSING) {
            return "Processing";
        } else {
            return "Coming Soon";
        }
    }

    /**
   * @dev See {IERC721Metadata-tokenURI}.
   */
    function tokenURI(uint256 tokenId) override(ERC721) public view returns (string memory) {
        require(tokenId != 0, "Incorrect token id");
        require(tokenId <= _tokenIdCounter.current(), "Ticket does't exist");

        string memory json = Base64.encode(
            bytes(string(
                abi.encodePacked(
                    '{',
                    '"name": "CryptoTron Ticket #', Strings.toString(tokenId), ' ' , unicode"—" , ' ', getLotteryStatus() ,'",',
                    '"image": "https://ipfs.io/ipfs/QmWVGGW5GGoczosF8oLWnBsAddT9MQ45VSd5cZHZkWcevj?filename=winn.png",',
                    '"attributes": [{"trait_type": "Chance", "value": "1 to 25" },',
                    '{"trait_type": "Prize", "value": "0.1 ETH" },',
                    '{"trait_type": "Project", "value": "Cryptotron" },',
                    '{"trait_type": "Draw State", "value": "', getDrawState(tokenId), '" },',
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
   * @dev used for setting lottery contract
   */
    function _setLotteryAddress(address _lotteryAddress) public onlyOwner {
        lotteryAddress = payable(_lotteryAddress);
    }

    /**
   * Hook, which is being used for implementing IERC721Receiver
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

    //
    function setDrawDate(uint256 _drawDate) external onlyLottery {
        drawDate = _drawDate;
    }

    function setStateOpen() external onlyLottery {
        s_lotteryState = lotteryState.OPEN;
    }

    //
    function setStateProcessing() external onlyLottery {
        s_lotteryState = lotteryState.PROCESSING;
    }

    //
    function setStateOver() external onlyLottery {
        s_lotteryState = lotteryState.OVER;
    }

    //
    function setWinnerId(uint256 _winnerId) external onlyLottery {
        winnerId = _winnerId;
    }

    /**
   * @dev Function that's being used by lottery contract to get the amount of participating tickets
   */
    function getSoldTicketsCount() external view returns (uint256) {
        return _tokenIdCounter.current();
    }
}