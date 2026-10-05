// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract MyDAO is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    constructor(
        IVotes token,
        uint32 votingPeriod_,
        uint256 proposalThreshold_
    )
        Governor("MyDAO")
        GovernorSettings(
            1,
            votingPeriod_,
            proposalThreshold_
        )
        GovernorVotes(token)
        GovernorVotesQuorumFraction(4)
    {}

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(
        uint256 timepoint
    ) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256)
    {
        return super.proposalThreshold();
    }
}