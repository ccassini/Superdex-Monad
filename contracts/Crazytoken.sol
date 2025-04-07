// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Crazytoken is ERC20, Ownable {
    uint256 private constant INITIAL_SUPPLY = 100000000 * 10 ** 18; // 100 million tokens
    
    // Events
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    
    constructor() ERC20("CRAZY", "CRAZY") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
    
    // Core token functions
    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }
} 