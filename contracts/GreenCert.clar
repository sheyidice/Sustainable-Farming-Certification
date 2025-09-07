;; title: GreenCert
;; version: 1.0.0
;; summary: Sustainable Farming Certification Protocol
;; description: A protocol for issuing and verifying on-chain certifications for farms that meet specific sustainability criteria.

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_FARM_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_CERTIFIED (err u102))
(define-constant ERR_CERTIFICATION_EXPIRED (err u103))
(define-constant ERR_INVALID_CRITERIA (err u104))
(define-constant ERR_AUTHORITY_NOT_FOUND (err u105))
(define-constant ERR_AUTHORITY_SUSPENDED (err u106))
(define-constant CERTIFICATION_DURATION u52560)

(define-data-var contract-owner principal CONTRACT_OWNER)
(define-data-var certification-fee uint u1000000)
(define-data-var total-farms uint u0)
(define-data-var total-certifications uint u0)

(define-map farms
  { farm-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    location: (string-ascii 128),
    size-hectares: uint,
    registered-at: uint,
    active: bool
  }
)

(define-map certifications
  { farm-id: uint }
  {
    certification-id: uint,
    authority: principal,
    criteria-met: (list 10 (string-ascii 32)),
    score: uint,
    issued-at: uint,
    expires-at: uint,
    valid: bool
  }
)

(define-map certification-authorities
  { authority: principal }
  {
    name: (string-ascii 64),
    accredited: bool,
    suspended: bool,
    certifications-issued: uint,
    registered-at: uint
  }
)

(define-map certification-criteria
  { criteria-id: uint }
  {
    name: (string-ascii 32),
    description: (string-ascii 128),
    weight: uint,
    active: bool
  }
)

(define-map farm-owner-lookup
  { owner: principal }
  { farm-ids: (list 50 uint) }
)

(define-public (register-farm (name (string-ascii 64)) (location (string-ascii 128)) (size-hectares uint))
  (let (
    (farm-id (+ (var-get total-farms) u1))
    (current-block burn-block-height)
  )
    (map-set farms
      { farm-id: farm-id }
      {
        owner: tx-sender,
        name: name,
        location: location,
        size-hectares: size-hectares,
        registered-at: current-block,
        active: true
      }
    )
    (var-set total-farms farm-id)
    (let ((existing-farms (default-to (list) (get farm-ids (map-get? farm-owner-lookup { owner: tx-sender })))))
      (map-set farm-owner-lookup
        { owner: tx-sender }
        { farm-ids: (unwrap! (as-max-len? (append existing-farms farm-id) u50) ERR_INVALID_CRITERIA) }
      )
    )
    (ok farm-id)
  )
)

(define-public (register-authority (name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set certification-authorities
      { authority: tx-sender }
      {
        name: name,
        accredited: true,
        suspended: false,
        certifications-issued: u0,
        registered-at: burn-block-height
      }
    )
    (ok true)
  )
)

(define-public (issue-certification 
  (farm-id uint) 
  (criteria-met (list 10 (string-ascii 32))) 
  (score uint)
)
  (let (
    (farm (unwrap! (map-get? farms { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (authority (unwrap! (map-get? certification-authorities { authority: tx-sender }) ERR_AUTHORITY_NOT_FOUND))
    (current-block burn-block-height)
    (cert-id (+ (var-get total-certifications) u1))
  )
    (asserts! (get accredited authority) ERR_NOT_AUTHORIZED)
    (asserts! (not (get suspended authority)) ERR_AUTHORITY_SUSPENDED)
    (asserts! (get active farm) ERR_FARM_NOT_FOUND)
    (asserts! (<= score u100) ERR_INVALID_CRITERIA)
    
    (match (map-get? certifications { farm-id: farm-id })
      existing-cert (asserts! (< (get expires-at existing-cert) current-block) ERR_ALREADY_CERTIFIED)
      true
    )
    
    (map-set certifications
      { farm-id: farm-id }
      {
        certification-id: cert-id,
        authority: tx-sender,
        criteria-met: criteria-met,
        score: score,
        issued-at: current-block,
        expires-at: (+ current-block CERTIFICATION_DURATION),
        valid: true
      }
    )
    
    (map-set certification-authorities
      { authority: tx-sender }
      (merge authority { certifications-issued: (+ (get certifications-issued authority) u1) })
    )
    
    (var-set total-certifications cert-id)
    (ok cert-id)
  )
)

(define-public (revoke-certification (farm-id uint))
  (let (
    (cert (unwrap! (map-get? certifications { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
  )
    (asserts! (or 
      (is-eq tx-sender (get authority cert))
      (is-eq tx-sender (var-get contract-owner))
    ) ERR_NOT_AUTHORIZED)
    
    (map-set certifications
      { farm-id: farm-id }
      (merge cert { valid: false })
    )
    (ok true)
  )
)

(define-public (suspend-authority (authority principal))
  (let (
    (auth-data (unwrap! (map-get? certification-authorities { authority: authority }) ERR_AUTHORITY_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set certification-authorities
      { authority: authority }
      (merge auth-data { suspended: true })
    )
    (ok true)
  )
)

(define-public (update-farm-status (farm-id uint) (active bool))
  (let (
    (farm (unwrap! (map-get? farms { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get owner farm)) ERR_NOT_AUTHORIZED)
    (map-set farms
      { farm-id: farm-id }
      (merge farm { active: active })
    )
    (ok true)
  )
)

(define-public (pay-certification-fee (farm-id uint))
  (let (
    (farm (unwrap! (map-get? farms { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (fee (var-get certification-fee))
  )
    (asserts! (is-eq tx-sender (get owner farm)) ERR_NOT_AUTHORIZED)
    (try! (stx-transfer? fee tx-sender (var-get contract-owner)))
    (ok true)
  )
)

(define-public (set-certification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (var-set certification-fee new-fee)
    (ok true)
  )
)

(define-read-only (get-farm (farm-id uint))
  (map-get? farms { farm-id: farm-id })
)

(define-read-only (get-certification (farm-id uint))
  (map-get? certifications { farm-id: farm-id })
)

(define-read-only (get-authority (authority principal))
  (map-get? certification-authorities { authority: authority })
)

(define-read-only (is-certified (farm-id uint))
  (match (map-get? certifications { farm-id: farm-id })
    cert (and 
      (get valid cert)
      (> (get expires-at cert) burn-block-height)
    )
    false
  )
)

(define-read-only (get-certification-status (farm-id uint))
  (match (map-get? certifications { farm-id: farm-id })
    cert {
      certified: (and (get valid cert) (> (get expires-at cert) burn-block-height)),
      score: (get score cert),
      expires-at: (get expires-at cert),
      authority: (get authority cert)
    }
    {
      certified: false,
      score: u0,
      expires-at: u0,
      authority: (var-get contract-owner)
    }
  )
)

(define-read-only (get-farms-by-owner (owner principal))
  (map-get? farm-owner-lookup { owner: owner })
)

(define-read-only (get-contract-stats)
  {
    total-farms: (var-get total-farms),
    total-certifications: (var-get total-certifications),
    certification-fee: (var-get certification-fee),
    contract-owner: (var-get contract-owner)
  }
)

(define-read-only (calculate-certification-score (criteria-count uint) (total-criteria uint))
  (if (> total-criteria u0)
    (/ (* criteria-count u100) total-criteria)
    u0
  )
)

(define-private (is-certification-expired (expires-at uint))
  (<= expires-at burn-block-height)
)

(define-private (validate-criteria-list (criteria (list 10 (string-ascii 32))))
  (> (len criteria) u0)
)

(define-private (calculate-renewal-discount (farm-id uint))
  (match (map-get? certifications { farm-id: farm-id })
    cert (if (>= (get score cert) u80) u10 u0)
    u0
  )
)
