pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Mock is ERC1155 {
    constructor() ERC1155("") {}

    function setURI(string memory newuri) public {
        _setURI(newuri);
    }

    function mint(
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public {
        _mint(to, id, value, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public {
        _mintBatch(to, ids, values, data);
    }

    function burn(
        address owner,
        uint256 id,
        uint256 value
    ) public {
        _burn(owner, id, value);
    }

    function burnBatch(
        address owner,
        uint256[] memory ids,
        uint256[] memory values
    ) public {
        _burnBatch(owner, ids, values);
    }

    function transferInternal(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) public {
        _safeTransferFrom(from, to, id, amount, "");
    }

    function transferBatchInternal(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public {
        _safeBatchTransferFrom(from, to, ids, amounts, "");
    }

    function approveInternal(
        address owner,
        address spender,
        bool approved
    ) public {
        _setApprovalForAll(owner, spender, approved);
    }
}
