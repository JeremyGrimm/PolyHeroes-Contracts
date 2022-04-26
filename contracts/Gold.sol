// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// GoldToken
contract Gold is Ownable, ERC20('Gold', 'Gold') {


mapping(address => bool) public whitelisted;


    modifier onlyWhitelist() {
        require(whitelisted[_msgSender()] == true, "Not Whitelisted Address");
        _;
    }

    function mint(address _to, uint256 _amount) public onlyWhitelist {
        _mint(_to, _amount);
    }

    function whitelist(address _user) external onlyOwner {
   whitelisted[_user] = true;
}


}