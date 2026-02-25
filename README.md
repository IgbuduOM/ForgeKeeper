# ForgeKeeper - In-Game Item Crafting & Provenance Ledger

## Overview

ForgeKeeper is a Clarity smart contract for the Stacks blockchain that implements a trustless in-game item crafting and provenance tracking system. Smiths forge items with verifiable crafting recipes and material proofs, appraisers assign quality grades during a public grading window, and the entire crafting history is permanently recorded on-chain.

This contract is purpose-built for blockchain gaming ecosystems where item authenticity, rarity verification, and crafting provenance are critical to maintaining a fair in-game economy. Every forged item carries an immutable record of its origin, materials used, and the quality assessments it received.

## Architecture

### Design Philosophy

ForgeKeeper treats in-game items as **first-class economic assets** rather than simple database entries. By recording crafting recipes, material manifests, and quality grades on-chain, the contract creates an unforgeable provenance chain that players, marketplaces, and game servers can independently verify.

The grading mechanism introduces a decentralized quality assurance layer. Instead of a single authority determining item rarity, multiple appraisers compete to assign the most accurate quality grade, with higher grades taking precedence. This creates a natural market for expertise in item evaluation.

### System Roles

- **Smiths**: Players or automated systems that forge new items by providing a recipe hash (proving they followed a valid crafting path), a material manifest (documenting consumed resources), and a material cost floor that establishes the minimum viable quality grade.
- **Appraisers**: Independent evaluators who inspect forged items and submit quality grades. Appraisers compete by submitting progressively higher grades, with the highest grade and its submitter permanently recorded.
- **Guild Master**: The protocol administrator with exclusive authority over forge taxation parameters. The guild master role is assigned at contract deployment and governs the economic overhead applied to all item transactions.

### Item Lifecycle

1. **Forging**: A smith calls `forge-item` providing the item name, recipe hash, material manifest, grading period (in blocks), and minimum material cost. The item enters the catalog with grading immediately open.
2. **Appraisal**: During the grading window, appraisers call `appraise-item` with their quality grade. The first appraisal must meet or exceed the material cost floor; subsequent appraisals must exceed the current peak grade.
3. **Seal Grading**: The smith may call `seal-grading` at any point during the grading window to lock the item at its current peak grade. This is useful when the smith is satisfied with the current appraisal.
4. **Retirement**: If no appraisals have been submitted, the smith may call `retire-item` to remove the item from active consideration. Retired items remain in the catalog for provenance purposes but cannot receive further appraisals.
5. **Expiry**: When the grading window closes (block height exceeds `grading-closes`), the item's grading automatically completes with whatever peak grade was achieved.

### Forge Taxation

The forge tax is a configurable fee expressed in basis points (100 bps = 1%). It is designed for integrating contracts to apply when items are traded or transferred. The tax rate is capped at 10% (1000 bps) and can only be adjusted by the guild master.

## Contract Interface

### Read-Only Functions

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `get-catalog-item` | `catalog-entry: uint` | `optional {...}` | Returns the complete item record including smith, name, recipe, materials, and grading state |
| `get-appraiser-grade` | `catalog-entry: uint, appraiser: principal` | `optional {...}` | Returns a specific appraiser's quality grade and grading block |
| `item-cataloged` | `catalog-entry: uint` | `bool` | Checks whether an item exists in the catalog |
| `is-grading-active` | `catalog-entry: uint` | `bool` | Returns true if the item is accepting appraisals and within the grading window |
| `is-grading-complete` | `catalog-entry: uint` | `bool` | Returns true if the block height has passed the grading deadline |
| `get-next-catalog-entry` | none | `uint` | Returns the next available catalog entry number |
| `get-forge-tax-bps` | none | `uint` | Returns the current forge tax rate in basis points |
| `compute-forge-tax` | `sale-price: uint` | `uint` | Calculates the tax amount for a given sale price |

### Public Functions

| Function | Parameters | Description |
|----------|-----------|-------------|
| `forge-item` | `item-name, recipe-hash, material-manifest, grading-period, material-cost` | Forges a new item and opens it for appraisal |
| `appraise-item` | `catalog-entry, quality-grade` | Submits a quality grade for an active item |
| `seal-grading` | `catalog-entry` | Closes grading early (smith only) |
| `retire-item` | `catalog-entry` | Retires an unappraised item (smith only) |
| `set-forge-tax` | `new-tax-bps` | Updates the forge tax rate (guild master only) |

## Error Reference

| Code | Constant | Description |
|------|----------|-------------|
| u1200 | `err-forge-access-denied` | Insufficient permissions for the requested forge operation |
| u1201 | `err-item-already-forged` | Item with this identifier already exists in the catalog |
| u1202 | `err-item-not-cataloged` | Referenced item does not exist in the catalog |
| u1203 | `err-appraisal-complete` | Grading window has already closed for this item |
| u1205 | `err-grade-below-standard` | Submitted grade does not meet the minimum requirement |
| u1207 | `err-not-smith` | Caller is not the smith who forged this item |
| u1209 | `err-grading-window-passed` | Grading period parameter must be greater than zero |
| u1211 | `err-guild-only` | Operation restricted to the guild master |
| u1212 | `err-forge-sealed` | Item grading has already been sealed or retired |
| u1213-u1215 | `err-blank-*` | Required string fields cannot be empty |

## Deployment

```bash
clarinet contract-deploy contracts/forge-keeper.clar
```

## Usage Example

```clarity
;; Forge a legendary sword
(contract-call? .forge-keeper forge-item
  "Blade of the Ancients"
  "sha256:abc123recipe..."
  "iron-ore:5,dragon-scale:2,enchant-dust:10"
  u144  ;; ~1 day grading window
  u500  ;; minimum 500 material cost floor
)
```

## Testing

```bash
clarinet test
```
