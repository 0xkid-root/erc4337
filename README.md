# ERC4337A

Rather than treating smart accounts as just wallets, ERC4337A transforms them into an AI agent's complete digital identity that serves as the on-chain representation of its capabilities, history, and reputation. This extension enables autonomous, composable, and secure multi-agent systems while preserving identity continuity through underlying model changes. ERC4337A is an integral part of the HyperAgent protocol.

## Multi-Agent Systems
ERC4337A transforms the smart account from a single-entity wallet into a multi-agent system (MAS). The primary agent defines rules of engagement, while sub-agents operate within those constraints.

The sub-agent system consists of three core components: the delegation module installed on the main account, a sub-agent factory, and specialized sub-agent accounts.

The delegation module can be installed on the main account to manage sub-agent permissions. Sub-agents do not rely on their own signer keys—instead, their operations are validated against rules defined in the parent's delegation module.

## Session Key Module
To interact with less-trusted or unaudited protocols, agents can generate session keys—temporary keys with limited permissions. A session key may be valid for a specific duration (e.g., 24 hours) and restricted to certain contracts or spending limits (e.g., 0.5 ETH).

Session keys and sub-agents are complementary: sub-agents create new structural identities, while session keys grant limited authority to existing entities. Together, they enable fine-grained control over agent actions and significantly reduce the attack surface in case of compromise.

Moreover, the system is fully composable: sub-agents can themselves create session keys and deploy further sub-agents, enabling complex, hierarchical operations.

## Swarm Intelligence
Sub-agents can generate their own session keys and deploy additional sub-agents, creating recursive hierarchies of specialized entities. This composability enables natural emergence of agent swarms when autonomous agents coordinate themselves.

This emergent behavior opens possibilities for decentralized autonomous organizations of AI agents, where collective intelligence emerges from individual agent interactions guided by economic incentives and reputation mechanisms.