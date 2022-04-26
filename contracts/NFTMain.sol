// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

interface ERC721TokenReceiver {
    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external returns(bytes4);
}

library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        require(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        return a - b;
    }


    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a);
        return c;
    }
}

contract NFTmain is Ownable, IERC721 {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Mint(uint indexed index, address indexed minter);

    bytes4 internal constant MAGIC_ON_ERC721_RECEIVED = 0x150b7a02;

    uint public constant TOKEN_LIMIT = 20000;

    mapping(bytes4 => bool) internal supportedInterfaces;

    mapping (uint256 => address) internal idToOwner;

    mapping (uint256 => address) internal idToApproval;

    mapping (address => mapping (address => bool)) internal ownerToOperators;

    mapping(address => uint256[]) internal ownerToIds;

    mapping(uint256 => uint256) internal idToOwnerIndex;

    string internal nftName = "PolyHeroes";
    string internal nftSymbol = "PolyHeroes";


    uint internal numTokens = 0;
    uint internal numSales = 0;
    uint public  remainderOfPrimary = 10000;
    uint public  remainderOfGold = 10000;

    address payable internal deployer;
    address payable internal marketer;
    address payable internal developer;
    bool public publicSale = false;
    uint private mintPrice = 0.02 ether;
    uint private goldMintPrice = 100 ether;
    string public baseUri;
    IERC20 public gold;
    uint public saleStartTime;

    uint internal nonce = 0;
    uint[TOKEN_LIMIT] internal indices;

    bool private reentrancyLock = false;

    modifier reentrancyGuard {
        if (reentrancyLock) {
            revert();
        }
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }

    modifier canOperate(uint256 _tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == msg.sender || ownerToOperators[tokenOwner][msg.sender], "Cannot operate.");
        _;
    }

    modifier canTransfer(uint256 _tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(
            tokenOwner == msg.sender
            || idToApproval[_tokenId] == msg.sender
            || ownerToOperators[tokenOwner][msg.sender], "Cannot transfer."
        );
        _;
    }

    modifier validNFToken(uint256 _tokenId) {
        require(idToOwner[_tokenId] != address(0), "Invalid token.");
        _;
    }

    constructor(address payable _marketer, address payable _developer, address gold_, uint256 _fee, address _feeAddress) {
        supportedInterfaces[0x01ffc9a7] = true; // ERC165
        supportedInterfaces[0x80ac58cd] = true; // ERC721
        supportedInterfaces[0x780e9d63] = true; // ERC721 Enumerable
        supportedInterfaces[0x5b5e139f] = true; // ERC721 Metadata
        baseFee = _fee;
        feeWallet = _feeAddress;
        marketer = _marketer;
        developer = _developer;
        gold = IERC20(gold_);
    }

    function startSale() external onlyOwner {
        require(!publicSale);
        saleStartTime = block.timestamp;
        publicSale = true;
    }

    function isContract(address _addr) internal view returns (bool addressCheck) {
        uint256 size;
        assembly { size := extcodesize(_addr) } // solhint-disable-line
        addressCheck = size > 0;
    }

    function supportsInterface(bytes4 _interfaceID) external view override returns (bool) {
        return supportedInterfaces[_interfaceID];
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata _data) external override {
        _safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external override {
        _safeTransferFrom(_from, _to, _tokenId, "");
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) external override canTransfer(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from, "Wrong from address.");
        require(_to != address(0), "Cannot send to 0x0.");
        _transfer(_to, _tokenId);
    }

    address public dungeonContract;

    function setDungeonContract (address _dungeonContract) public onlyOwner {
        dungeonContract = _dungeonContract;
    }

        function transferToDungeon(address _from, address _to, uint256 _tokenId) external validNFToken(_tokenId) {
        require(_to == address(this) || _to == dungeonContract);
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from, "Wrong from address.");
        require(_to != address(0), "Cannot send to 0x0.");
        _transfer(_to, _tokenId);
    }

    function approve(address _approved, uint256 _tokenId) external override canOperate(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(_approved != tokenOwner);
        idToApproval[_tokenId] = _approved;
        emit Approval(tokenOwner, _approved, _tokenId);
    }

    function setApprovalForAll(address _operator, bool _approved) external override {
        ownerToOperators[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function balanceOf(address _owner) external view override returns (uint256) {
        require(_owner != address(0));
        return _getOwnerNFTCount(_owner);
    }

    function ownerOf(uint256 _tokenId) public view override returns (address _owner) {
        require(idToOwner[_tokenId] != address(0));
        _owner = idToOwner[_tokenId];
    }

    function getApproved(uint256 _tokenId) external view override validNFToken(_tokenId) returns (address) {
        return idToApproval[_tokenId];
    }

    function isApprovedForAll(address _owner, address _operator) external override view returns (bool) {
        return ownerToOperators[_owner][_operator];
    }

    function canUse (uint256 _tokenId, address _check) public view returns (bool)  {
        address tokenOwner = idToOwner[_tokenId];
        if(
            tokenOwner == _check
            || idToApproval[_tokenId] == _check
            || ownerToOperators[tokenOwner][_check]
        ) {return true;} else {return false;}

    }

    function _transfer(address _to, uint256 _tokenId) internal {
        address from = idToOwner[_tokenId];
        _clearApproval(_tokenId);
        _removeListing(_tokenId);
        _removeNFToken(from, _tokenId);
        _addNFToken(_to, _tokenId);

        emit Transfer(from, _to, _tokenId);
    }

    function randomIndex() internal returns (uint) {
        uint totalSize = TOKEN_LIMIT - numTokens;
        uint index = uint(keccak256(abi.encodePacked(nonce, msg.sender, block.difficulty, block.timestamp))) % totalSize;
        uint value = 0;
        if (indices[index] != 0) {
            value = indices[index];
        } else {
            value = index;
        }

        // Move last value to selected position
        if (indices[totalSize - 1] == 0) {
            // Array position not initialized, so use position
            indices[index] = totalSize - 1;
        } else {
            // Array position holds a value so use that
            indices[index] = indices[totalSize - 1];
        }
        nonce++;
        // Don't allow a zero index, start counting at 1
        return value.add(1);
    }

    function mintsRemaining() external view returns (uint) {
        return TOKEN_LIMIT.sub(numSales);
    }


        function publicMint (uint256 numberOfNfts) external payable reentrancyGuard {
        require(publicSale, "Sale not started.");
        require(numberOfNfts <= 20, "You can not buy more than 20 NFTs at once");
        require(totalSupply().add(numberOfNfts) <= TOKEN_LIMIT, "Exceeds TOKEN_LIMIT");
        require(remainderOfPrimary.sub(numberOfNfts) >= 0, "Exceeds remaining primary sale of MATIC sale");
        require(mintPrice.mul(numberOfNfts) == msg.value, "MATIC value sent is not correct");

        
        marketer.transfer(msg.value.div(2));
        developer.transfer(msg.value.div(2));
        
        for (uint i = 0; i < numberOfNfts; i++) {
            numSales++;
            remainderOfPrimary = remainderOfPrimary - 1;
            _mint(msg.sender);
        }
        
    }


        function Goldmint(uint256 numberOfNfts) external payable reentrancyGuard {
        require(publicSale, "Sale not started.");
        require(numberOfNfts <= 20, "You can not buy more than 20 NFTs at once");
        require(totalSupply().add(numberOfNfts) <= TOKEN_LIMIT, "Exceeds TOKEN_LIMIT");
        require(remainderOfGold.sub(numberOfNfts) >= 0, "Exceeds remaining primary sale of MATIC sale");
        
        gold.safeTransferFrom(msg.sender, address(this), goldMintPrice.mul(numberOfNfts));
        
        for (uint i = 0; i < numberOfNfts; i++) {
            numSales++;
            remainderOfGold = remainderOfGold - 1;
            _mint(msg.sender);
        }
        
    }

    function _mint(address _to) internal returns (uint) {
        require(_to != address(0), "Cannot mint to 0x0.");
        require(numTokens < TOKEN_LIMIT, "Token limit reached.");
        uint id = randomIndex();

        numTokens = numTokens + 1;
        _addNFToken(_to, id);

        emit Mint(id, _to);
        emit Transfer(address(0), _to, id);
        return id;
    }

    function _addNFToken(address _to, uint256 _tokenId) internal {
        require(idToOwner[_tokenId] == address(0), "Cannot add, already owned.");
        idToOwner[_tokenId] = _to;

        ownerToIds[_to].push(_tokenId);
        idToOwnerIndex[_tokenId] = ownerToIds[_to].length.sub(1);
    }

    function _removeNFToken(address _from, uint256 _tokenId) internal {
        require(idToOwner[_tokenId] == _from, "Incorrect owner.");
        delete idToOwner[_tokenId];

        uint256 tokenToRemoveIndex = idToOwnerIndex[_tokenId];
        uint256 lastTokenIndex = ownerToIds[_from].length.sub(1);

        if (lastTokenIndex != tokenToRemoveIndex) {
            uint256 lastToken = ownerToIds[_from][lastTokenIndex];
            ownerToIds[_from][tokenToRemoveIndex] = lastToken;
            idToOwnerIndex[lastToken] = tokenToRemoveIndex;
        }

        ownerToIds[_from].pop();
    }

    function _getOwnerNFTCount(address _owner) internal view returns (uint256) {
        return ownerToIds[_owner].length;
    }

    function _safeTransferFrom(address _from,  address _to,  uint256 _tokenId,  bytes memory _data) private canTransfer(_tokenId) validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from, "Incorrect owner.");
        require(_to != address(0));

        _transfer(_to, _tokenId);

        if (isContract(_to)) {
            bytes4 retval = ERC721TokenReceiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data);
            require(retval == MAGIC_ON_ERC721_RECEIVED);
        }
    }
    
    function _safeTransfer(address _from,  address _to,  uint256 _tokenId,  bytes memory _data) private validNFToken(_tokenId) {
        address tokenOwner = idToOwner[_tokenId];
        require(tokenOwner == _from, "Incorrect owner.");
        require(_to != address(0));

        _transfer(_to, _tokenId);

        if (isContract(_to)) {
            bytes4 retval = ERC721TokenReceiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data);
            require(retval == MAGIC_ON_ERC721_RECEIVED);
        }
    }

    function _clearApproval(uint256 _tokenId) private {
        if (idToApproval[_tokenId] != address(0)) {
            delete idToApproval[_tokenId];
        }
    }

    function totalSupply() public view returns (uint256) {
        return numTokens;
    }

    function tokenByIndex(uint256 index) public pure returns (uint256) {
        require(index >= 0 && index < TOKEN_LIMIT);
        return index + 1;
    }

    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
        require(_index < ownerToIds[_owner].length);
        return ownerToIds[_owner][_index];
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + temp % 10));
            temp /= 10;
        }
        return string(buffer);
    }

    function name() external view returns (string memory _name) {
        _name = nftName;
    }

    function symbol() external view returns (string memory _symbol) {
        _symbol = nftSymbol;
    }


    function tokenURI(uint256 _tokenId) external view validNFToken(_tokenId) returns (string memory) {
        return string(abi.encodePacked(baseUri, toString(_tokenId)));
    }

    function setUri (string memory newUri) public onlyOwner {
        baseUri = newUri;
    }

        /*
            Market (initially a seperate contract so sorry if it is messy
        */

    struct listing {
    bool isForSale;
    address owner;
    uint256 price; //in wei
    uint256 purchaseTokenId;
    }

    mapping (uint256 => listing) public list;

    mapping (uint256 => IERC20) public purchaseToken;

    //variable

    uint256 public baseFee;
    address public feeWallet;
    bool public marketStatus = false;


    //events

    event listingCreated (uint256 _tokenId, uint256 _price, uint256 purchaseTokenId);
    event listingRemoved (uint256 _tokenId);
    event NFTbought (uint256 _tokenId, uint256 price, uint256 purchaseTokenId);

    //main functions

    uint256 [] public nftList;

    function getNftAddress()public view returns( uint256  [] memory){
    return nftList;
}

    function createListing (uint256 _price, uint256 _tokenId, uint256 _purchaseTokenId) public {
        require(marketStatus, "Market not started");
        require(ownerOf(_tokenId) == _msgSender(), "You are not the owner of the token");
        list[_tokenId] = listing(true, msg.sender, _price, _purchaseTokenId);
        emit listingCreated(_tokenId, _price, _purchaseTokenId);
        nftList.push(_tokenId);
    }

    function removeListing (uint256 _tokenId) public {
        require(marketStatus, "Market not started");
        require(ownerOf(_tokenId) == _msgSender(), "You are not the owner of the token");
        list[_tokenId] = listing(false, address(0), 0, 0);
        emit listingRemoved(_tokenId);
        for( uint256 i = 0; i < nftList.length; i++){                              
        if ( nftList[i] == _tokenId) { 
            delete nftList[i];
        }
    }
    }

    function buyNFTWithToken (uint256 _tokenId) public {
        require(marketStatus, "Market not started");
        require(list[_tokenId].isForSale, "The token is not for sale");
        require(list[_tokenId].purchaseTokenId != 0, "Error with token payment");
        require(purchaseToken[list[_tokenId].purchaseTokenId].balanceOf(msg.sender) >= list[_tokenId].price, "You do not own enough gold" );
        require(purchaseToken[list[_tokenId].purchaseTokenId].allowance(msg.sender, address(this)) >= list[_tokenId].price, "You allowance is too small");
        uint256 fee = baseFee;
        uint256 amountAfterFee = 1000 - fee;
        purchaseToken[list[_tokenId].purchaseTokenId].safeTransferFrom(msg.sender, feeWallet, list[_tokenId].price.mul(fee).div(1000));
        purchaseToken[list[_tokenId].purchaseTokenId].safeTransferFrom(msg.sender, list[_tokenId].owner, list[_tokenId].price.mul(amountAfterFee).div(1000));
        _transfer(msg.sender, _tokenId);
        emit NFTbought(_tokenId, list[_tokenId].price, list[_tokenId].purchaseTokenId);
        list[_tokenId] = listing(false, address(0), 0, 0);
                for( uint256 i = 0; i < nftList.length; i++){                              
        if ( nftList[i] == _tokenId) { 
            delete nftList[i];
        }
    }
    }

    function buyNFTMatic (uint256 _tokenId) public payable {
        require(marketStatus, "Market not started");
        require(list[_tokenId].isForSale, "The token is not for sale");
        require(list[_tokenId].purchaseTokenId == 0, "Not listed in Matic");
        require(msg.value == list[_tokenId].price, "Wrong amount of Matic sent");
        uint256 fee = baseFee;
        uint256 amountAfterFee = 1000 - fee;
        payable(feeWallet).transfer(list[_tokenId].price.mul(fee).div(1000));
        payable(list[_tokenId].owner).transfer(list[_tokenId].price.mul(amountAfterFee).div(1000));
        _transfer( msg.sender, _tokenId);
        emit NFTbought(_tokenId, list[_tokenId].price, list[_tokenId].purchaseTokenId);
        list[_tokenId] = listing(false, address(0), 0, 0);
        for( uint256 i = 0; i < nftList.length; i++){                              
        if ( nftList[i] == _tokenId) { 
            delete nftList[i];
        }
    }
    }

    //internal function

    function _removeListing (uint256 _tokenId) internal {
        list[_tokenId] = listing(false, address(0), 0, 0);
    }

    //owner functions

    function setSale (bool _marketStatus) public onlyOwner {
        marketStatus = _marketStatus;
    }

    function setFee (uint256 _newBaseFee) public onlyOwner {
        baseFee = _newBaseFee;
    }

    function addPaymentToken (uint256 _paymentTokenId, address _tokenAddress) public onlyOwner {
        purchaseToken[_paymentTokenId] = IERC20(_tokenAddress);
    }

}

