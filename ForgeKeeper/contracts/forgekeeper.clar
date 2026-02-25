;; ForgeKeeper: In-Game Item Crafting & Provenance Ledger
;; A trustless item management system for:
;; 1. Smiths to forge items with crafting recipes and material proofs
;; 2. Appraisers to evaluate item rarity and assign quality grades
;; 3. Provenance tracking through immutable crafting history
;; 4. Guild master governance over forge taxation rates

(define-constant guild-master tx-sender)

;; Forge error signals
(define-constant err-forge-access-denied (err u1200))
(define-constant err-item-already-forged (err u1201))
(define-constant err-item-not-cataloged (err u1202))
(define-constant err-appraisal-complete (err u1203))
(define-constant err-appraisal-in-progress (err u1204))
(define-constant err-grade-below-standard (err u1205))
(define-constant err-not-appraiser (err u1206))
(define-constant err-not-smith (err u1207))
(define-constant err-appraisal-duplicate (err u1208))
(define-constant err-grading-window-passed (err u1209))
(define-constant err-material-cost-unmet (err u1210))
(define-constant err-guild-only (err u1211))
(define-constant err-forge-sealed (err u1212))
(define-constant err-blank-item-name (err u1213))
(define-constant err-blank-recipe-hash (err u1214))
(define-constant err-blank-material-manifest (err u1215))

;; Item catalog
(define-map item-catalog
  { catalog-entry: uint }
  {
    smith: principal,
    item-name: (string-ascii 64),
    recipe-hash: (string-ascii 256),
    material-manifest: (string-ascii 256),
    forged-at-block: uint,
    grading-closes: uint,
    material-cost: uint,
    peak-grade: uint,
    lead-appraiser: (optional principal),
    grading-active: bool,
    retired: bool
  }
)

(define-map appraiser-grades
  { catalog-entry: uint, appraiser: principal }
  { quality-grade: uint, graded-at-block: uint }
)

;; Catalog entry counter
(define-data-var catalog-counter uint u1)

;; Forge tax (1% = 100 basis points)
(define-data-var forge-tax-bps uint u100)

;; Catalog queries

(define-read-only (get-catalog-item (catalog-entry uint))
  (map-get? item-catalog { catalog-entry: catalog-entry })
)

(define-read-only (get-appraiser-grade (catalog-entry uint) (appraiser principal))
  (map-get? appraiser-grades { catalog-entry: catalog-entry, appraiser: appraiser })
)

(define-read-only (item-cataloged (catalog-entry uint))
  (is-some (get-catalog-item catalog-entry))
)

(define-read-only (is-grading-active (catalog-entry uint))
  (match (get-catalog-item catalog-entry)
    item-info (and
                (get grading-active item-info)
                (< block-height (get grading-closes item-info))
              )
    false
  )
)

(define-read-only (is-grading-complete (catalog-entry uint))
  (match (get-catalog-item catalog-entry)
    item-info (>= block-height (get grading-closes item-info))
    false
  )
)

(define-read-only (get-next-catalog-entry)
  (var-get catalog-counter)
)

(define-read-only (get-forge-tax-bps)
  (var-get forge-tax-bps)
)

(define-read-only (compute-forge-tax (sale-price uint))
  (/ (* sale-price (var-get forge-tax-bps)) u10000)
)

;; Internal helpers

(define-private (compute-smith-earnings (sale-price uint))
  (- sale-price (compute-forge-tax sale-price))
)

(define-private (valid-item-name (name (string-ascii 64)))
  (> (len name) u0)
)

(define-private (valid-recipe-hash (recipe (string-ascii 256)))
  (> (len recipe) u0)
)

(define-private (valid-material-manifest (manifest (string-ascii 256)))
  (> (len manifest) u0)
)

;; Forge operations

(define-public (forge-item
                (item-name (string-ascii 64))
                (recipe-hash (string-ascii 256))
                (material-manifest (string-ascii 256))
                (grading-period uint)
                (material-cost uint))
  (let ((catalog-entry (var-get catalog-counter))
        (forged-at-block block-height)
        (grading-closes (+ block-height grading-period)))
    (begin
      (asserts! (valid-item-name item-name) err-blank-item-name)
      (asserts! (valid-recipe-hash recipe-hash) err-blank-recipe-hash)
      (asserts! (valid-material-manifest material-manifest) err-blank-material-manifest)
      (asserts! (> grading-period u0) err-grading-window-passed)
      (asserts! (> material-cost u0) err-material-cost-unmet)

      (map-set item-catalog
        { catalog-entry: catalog-entry }
        {
          smith: tx-sender,
          item-name: item-name,
          recipe-hash: recipe-hash,
          material-manifest: material-manifest,
          forged-at-block: forged-at-block,
          grading-closes: grading-closes,
          material-cost: material-cost,
          peak-grade: u0,
          lead-appraiser: none,
          grading-active: true,
          retired: false
        }
      )

      (var-set catalog-counter (+ catalog-entry u1))

      (ok catalog-entry)
    )
  )
)

(define-public (appraise-item (catalog-entry uint) (quality-grade uint))
  (let ((item-info (unwrap! (get-catalog-item catalog-entry) err-item-not-cataloged)))
    (begin
      (asserts! (get grading-active item-info) err-forge-sealed)
      (asserts! (< block-height (get grading-closes item-info)) err-appraisal-complete)

      (asserts! (if (is-some (get lead-appraiser item-info))
                   (> quality-grade (get peak-grade item-info))
                   (>= quality-grade (get material-cost item-info)))
               err-grade-below-standard)

      (map-set appraiser-grades
        { catalog-entry: catalog-entry, appraiser: tx-sender }
        { quality-grade: quality-grade, graded-at-block: block-height }
      )

      (map-set item-catalog
        { catalog-entry: catalog-entry }
        (merge item-info {
          peak-grade: quality-grade,
          lead-appraiser: (some tx-sender)
        })
      )

      (ok true)
    )
  )
)

(define-public (seal-grading (catalog-entry uint))
  (let ((item-info (unwrap! (get-catalog-item catalog-entry) err-item-not-cataloged)))
    (begin
      (asserts! (is-eq tx-sender (get smith item-info)) err-not-smith)
      (asserts! (get grading-active item-info) err-forge-sealed)
      (asserts! (< block-height (get grading-closes item-info)) err-appraisal-complete)

      (map-set item-catalog
        { catalog-entry: catalog-entry }
        (merge item-info {
          grading-active: false,
          grading-closes: block-height
        })
      )

      (ok true)
    )
  )
)

(define-public (retire-item (catalog-entry uint))
  (let ((item-info (unwrap! (get-catalog-item catalog-entry) err-item-not-cataloged)))
    (begin
      (asserts! (is-eq tx-sender (get smith item-info)) err-not-smith)
      (asserts! (get grading-active item-info) err-forge-sealed)
      (asserts! (is-eq (get peak-grade item-info) u0) err-grade-below-standard)

      (map-set item-catalog
        { catalog-entry: catalog-entry }
        (merge item-info { grading-active: false })
      )

      (ok true)
    )
  )
)

;; Guild governance

(define-public (set-forge-tax (new-tax-bps uint))
  (begin
    (asserts! (is-eq tx-sender guild-master) err-guild-only)
    (asserts! (<= new-tax-bps u1000) err-forge-access-denied)
    (ok (var-set forge-tax-bps new-tax-bps))
  )
)
