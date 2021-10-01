// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "solmate/erc20/ERC20.sol";
import "../access/Warded.sol";

contract Mintable is ERC20, Warded {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) Warded() {}

    /**
     * See {ERC20-_mint}.
     * @param usr The address to send the minted tokens.
     * @param amount The amount to be minted.
     **/
    function mint(address usr, uint256 amount) public onlyWards {
        _mint(usr, amount);
        emit Mint(usr, amount);
    }

    /**
     * See {ERC20-_burn}.
     * @param usr The address from where to burn tokens from.
     * @param amount The amount to be burned.
     **/
    function burn(address usr, uint256 amount) public virtual {
        _burn(usr, amount);
        emit Burn(usr, amount);
    }

    /* ========== EVENTS ========== */
    event Mint(address usr, uint256 amount);
    event Burn(address usr, uint256 amount);
}
