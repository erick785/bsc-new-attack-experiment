# bsc-attack-experiment

## Introduction

Attack 1 Experiment layout:

Attack 1 starts a 21-validator local BSC cluster and splits it into two logical network partitions:

- Group A: node `0..9` plus the A-side instance of node `11`.
- Group B: node `10` and node `12..20`.
- Node `11` is intentionally duplicated. The original `node11` starts with Group A, while a copied `node11-b`
  instance is started later with Group B.

The script first builds the attack-1 `geth` binary and `create-validator`, resets the cluster, and starts the initial
21 validators. After the chain reaches height `201`, it adds extra validators on both sides:

- Group A adds validators `21..31`; registration transactions are sent through node0 RPC `8545`.
- Group B adds validators `32..41`; registration transactions are sent through node10 RPC `8555`.

After node0 reaches height `400`, the script starts the copied B-side `node11-b` instance with
`BSC_NETWORK_SPLIT_GROUP=B`. The experiment succeeds when both node0 and node10 observe a
`Parlia finalized block number changed` log after height `400`, showing that both partitions have advanced their
finalized block independently.

Simple sketch:

```text
  height
    ^
    |     Group A partition                              Group B partition
    |  node0..9 + node11(A)                         node10, node12..20
  0 |------------------------- common prefix -------------------------------> time
201 | + add validators 21..31 through node0 RPC 8545
    | + add validators 32..41 through node10 RPC 8555
400 | start copied node11-b with BSC_NETWORK_SPLIT_GROUP=B
    | A: finalized block changes on node0
    | B: finalized block changes on node10
    +---------------------------------------------------------------------> time
```


Attack 2 Experiment layout:

At block height 399, a block is produced by address 0x3ad... (this follows Parlia's natural in-turn schedule).
Starting from height 400, we enter the experiment window.
During the experiment, nodes no longer broadcast blocks freely; instead, they only send blocks via directed delivery
according to the routing table below: (height, miner) → target validator.

Two parallel chains:

```text
  difficulty :            2    →    1    →    2    →    2    →     1   →    1
  Chain A (no prime):  400(5e) → 401(f7) → 402(bb) → 403(bc) → 404(fe) → 405(5f)
```

```text
  difficulty :            1     →   2      →    1     →     1    →    1     →    1
  Chain B (prime):     400'(bc) → 401'(5f) → 402'(fe) → 403'(5e) → 404'(3a) → 405'(f7)
```

Broadcast routing:

```text
  400  5e → f7                                                          |  400' bc → 5f
  401  f7 → bb                                                          |  401' 5f → fe
  402  bb → bc (bc switches back from 400' to Chain A and produces 403) |  402' fe → 5e (5e switches back from 400 to Chain B and produces 403')
  403  bc → fe (fe switches back from 402' to Chain A and produces 404) |  403' 5e → 3a
  404  fe → 5f (5f switches back from 401' to Chain A and produces 405) |  404' 3a → f7
  405  5f → ∅ (do not broadcast)                                        |  405' f7 → ∅ (do not broadcast)
```

Design notes:
For every reorg recipient, the TD of the recipient's current chain is strictly smaller than the broadcast block's trueTD
(= block.TD - block.Diff). Only under this condition will chainSync.nextSyncOp trigger the downloader to fetch missing
ancestors. After the recipient finishes the reorg, it produces the next block according to the schedule.
After finishing 405/405', all nodes stop producing and broadcasting blocks; the experiment ends.

## 🚀 Quick Access

## 📦 Recommended Setup: Docker

### Prerequisites

### Running attack 1

### Running attack 2


## 🛠️ Optional: Manual Build & Execution

We also provide a fully manual setup method for users or reviewers who prefer to inspect and customize the testing environment (See [Appendix](#appendix)).

## 🧪 Attack Success Criteria

### For attack 1

The attack is considered successful when the script prints finalized block changes from both node0 and node10 after
height `400`, for example:

```text
[2026-05-04 17:51:43] node0 matched log line:
t=05-04|17:51:43.012 lvl=info msg="Parlia finalized block number changed" header=413 prevFinalized=396 newFinalized=411 targetNumber=412 sourceHash=0xa53b8dd08c1990b73388061b115d7332235f3d2d0d755ae1d25a83f4407ad6fa targetHash=0x0b616e141d5d0a4206f2e49ea71243538078665310a613afec5e4aaf138a585a
[2026-05-04 17:52:43] node10 matched log line:
t=05-04|17:52:43.035 lvl=info msg="Parlia finalized block number changed" header=430 prevFinalized=396 newFinalized=428 targetNumber=429 sourceHash=0x0047cf78fe366438f3a32b458bd40a6c78529b5cf47c254d3943800d41fda3fa targetHash=0x000fa3e16f902ec4cb769192186dd7952665fa412357c03bd8aee542b45673c2
```

### For attack 2


## 💻 Source Code

- BSC base (v1.6.6): [https://github.com/bnb-chain/bsc/tree/v1.6.6](https://github.com/bnb-chain/bsc/tree/v1.6.6)
  
  - attack 1 code : ./code/attack-1-code.zip
  - attack 2 code : ./code/attack-2-code.zip
- Node deployment script: [https://github.com/bnb-chain/node-deploy](https://github.com/bnb-chain/node-deploy)

## 📄Appendix

This section outlines the complete manual installation process, including environment setup, dependency installation, and attack execution using raw scripts and source code.

> ⚠️ **Before you begin**, please ensure the following software and system packages are installed on your local machine:

- Ubuntu 20.04/22.04
- nodejs: 18.20.2
- npm: 6.14.6
- go: 1.21+
- python3: 3.12+
- docker: 27.5.1
- foundry: 1.1.0
- poetry: 2.0.0
- jq: 1.7

### Setup steps

1. Unzip and enter the project directory

```bash
unzip node-deploy.zip
cd node-deploy
```

2. Create and activate a virtual environment

```
# Create the virtual environment (if the venv package is not installed)
python3 -m venv path/to/venv

# Create virtual environments
apt install python3.12-venv

# Activate the virtual environment
source path/to/venv/bin/activate
```

3. Install dependencies

```
chmod +x install-dev.sh
sudo ./install-dev.sh
pip3 install -r node-deploy/requirements.txt
```

4. Compile the geth binary, and place it in the node-deploy/bin/ folder

```bash
unzip ./code/attack-1-code.zip
cd attack-1-code && make geth
unzip node-deploy.zip
mv attack-1-code/build/bin/geth node-deploy/bin/geth
```

### Launching attack simulation

1. Start attack 1

```bash
cd node-deploy
./test_attack_1_flow.sh
```

The script performs the full attack-1 flow:

- Build the latest `code/attack-1-code` geth binary with `make geth`.
- Build `node-deploy/create-validator` with `go build`.
- Install the geth binary into `node-deploy/bin/geth`.
- Prepare the Python virtual environment and install `node-deploy/requirements.txt`.
- Reset and start the 21-node validator cluster.
- Wait for height `201`, then add Group A validators `21..31` through node0 RPC `8545`.
- Add Group B validators `32..41` through node10 RPC `8555`.
- Wait for height `400`, copy `node11` to `node11-b`, and start the B-side instance with
  `BSC_NETWORK_SPLIT_GROUP=B`.
- Monitor node0 and node10 logs until both print `Parlia finalized block number changed`.
- Stop the cluster with `bash -x ./bsc_cluster_1.sh stop`.

The run is successful when the terminal shows matched finalized-block-change logs for both node0 and node10, as
shown in the [attack success criteria](#for-attack-1).

We recommend running each attack in a clean and isolated environment to ensure independent evaluation. We do not recommend running different attacks in parallel under the same environment.

Please recompile the corresponding binary before running the following attacks.

2. Start attack 2

```bash
# attack 2
./test_attack_2_flow.sh # will start the attack 2 simulation
```

## 🐳 Building Docker Images

### Build Prerequisites

### Building Attack 1 Image

### Building Attack 2 Image

### Running Attacks Using Local Docker Images

## Contribution

- For questions or bug reports, please open a GitHub issue in this repository.
