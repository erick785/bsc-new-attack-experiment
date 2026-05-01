# bsc-attack-experiment

## Introduction

Attack 1 Experiment layout:

Starting at height 400, we intentionally split the network into two partitions so that validators in each partition
can only communicate within their own partition. Both partitions keep producing blocks independently, forming two competing branches.

At fork height 400 on both branches (i.e., starting from their respective `400` blocks), we register/add new validators on each side.
We then wait until the newly added validators begin proposing blocks in their own partition.
After that, we lift the network partition (restore connectivity). The observed behavior is that the two branches do not converge
into a single canonical chain; both branches can remain viable and persist.

Simple sketch:

```text
  height
    ^
    |     Partition A (isolated)                       Partition B (isolated)
    |           net A                                        net B
399 |------------------------- common prefix -------------------------------> time
400 | split; fork starts
    | + add new validators on branch A @ 400
    | + add new validators on branch B @ 400
401 | A: 400A -> 401A -> 402A -> ... -> (new validators propose)
    | B: 400B -> 401B -> 402B -> ... -> (new validators propose)
  t | restore connectivity (partition lifted)
    | Observation: A and B still do not converge; both branches can persist
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
# attack 1 
bash -x ./bsc_cluster.sh reset # will reset the cluster and start

```

We recommend running each attack in a clean and isolated environment to ensure independent evaluation. We do not recommend running different attacks in parallel under the same environment.

Please recompile the corresponding binary before running the following attacks.

2. Start attack 2

```bash
# attack 2
bash -x ./bsc_cluster.sh reset # will reset the cluster and start
```

## 🐳 Building Docker Images

### Build Prerequisites

### Building Attack 1 Image

### Building Attack 2 Image

### Building Attack 3 (Bootnode) Image

### Building Attack 3 (Static Node) Image

### Running Attacks Using Local Docker Images

## Contribution

- For questions or bug reports, please open a GitHub issue in this repository.
