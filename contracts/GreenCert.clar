;; title: GreenCert
;; version: 2.0.0
;; summary: Sustainable Farming Certification Protocol with RBAC & Multi-Signature Verification
;; description: A protocol for issuing and verifying on-chain certifications for farms that meet specific sustainability criteria, enhanced with role-based access control, supervisor approval workflows, secondary authority verification, and comprehensive action logging.

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_FARM_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_CERTIFIED (err u102))
(define-constant ERR_CERTIFICATION_EXPIRED (err u103))
(define-constant ERR_INVALID_CRITERIA (err u104))
(define-constant ERR_AUTHORITY_NOT_FOUND (err u105))
(define-constant ERR_AUTHORITY_SUSPENDED (err u106))
(define-constant ERR_NO_RENEWAL_AVAILABLE (err u107))
(define-constant ERR_NOT_SUPERVISOR (err u108))
(define-constant ERR_PENDING_APPROVAL (err u109))
(define-constant ERR_REQUIRES_SECONDARY (err u110))
(define-constant ERR_ALREADY_VERIFIED (err u111))
(define-constant ERR_NOT_SECONDARY_AUTHORITY (err u112))
(define-constant CERTIFICATION_DURATION u52560)
(define-constant RENEWAL_DISCOUNT_THRESHOLD u75)
(define-constant RENEWAL_DISCOUNT_RATE u10)
(define-constant SECONDARY_VERIFICATION_THRESHOLD u80)
(define-constant ACTION_TYPE_ISSUE u1)
(define-constant ACTION_TYPE_APPROVE u2)
(define-constant ACTION_TYPE_VERIFY_SECONDARY u3)
(define-constant ACTION_TYPE_REVOKE u4)
(define-constant ACTION_TYPE_REJECT u5)

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

(define-map certification-history
  { farm-id: uint, history-index: uint }
  {
    certification-id: uint,
    authority: principal,
    score: uint,
    issued-at: uint,
    expires-at: uint,
    archived-at: uint
  }
)

(define-map renewal-count
  { farm-id: uint }
  { count: uint }
)

(define-map cumulative-score
  { farm-id: uint }
  { total: uint }
)

(define-map supervisors
  { supervisor: principal }
  {
    registered-at: uint,
    active: bool
  }
)

(define-map pending-certifications
  { cert-pending-id: uint }
  {
    farm-id: uint,
    authority: principal,
    criteria-met: (list 10 (string-ascii 32)),
    score: uint,
    requested-at: uint,
    requires-secondary: bool,
    approved: bool,
    rejected: bool
  }
)

(define-map secondary-verifications
  { cert-id: uint }
  {
    primary-authority: principal,
    secondary-authority: principal,
    verified: bool,
    verified-at: uint
  }
)

(define-map action-logs
  { action-id: uint }
  {
    action-type: uint,
    performer: principal,
    farm-id: uint,
    cert-id: uint,
    block-height: uint
  }
)

(define-data-var pending-cert-counter uint u0)
(define-data-var action-log-counter uint u0)

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

(define-public (register-supervisor (supervisor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set supervisors
      { supervisor: supervisor }
      {
        registered-at: burn-block-height,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (remove-supervisor (supervisor principal))
  (let (
    (sup-data (unwrap! (map-get? supervisors { supervisor: supervisor }) ERR_NOT_SUPERVISOR))
  )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set supervisors
      { supervisor: supervisor }
      (merge sup-data { active: false })
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
    (pending-id (+ (var-get pending-cert-counter) u1))
    (requires-secondary (>= score SECONDARY_VERIFICATION_THRESHOLD))
    (action-id (+ (var-get action-log-counter) u1))
  )
    (asserts! (get accredited authority) ERR_NOT_AUTHORIZED)
    (asserts! (not (get suspended authority)) ERR_AUTHORITY_SUSPENDED)
    (asserts! (get active farm) ERR_FARM_NOT_FOUND)
    (asserts! (<= score u100) ERR_INVALID_CRITERIA)
    
    (match (map-get? certifications { farm-id: farm-id })
      existing-cert (asserts! (< (get expires-at existing-cert) current-block) ERR_ALREADY_CERTIFIED)
      true
    )
    
    (map-set pending-certifications
      { cert-pending-id: pending-id }
      {
        farm-id: farm-id,
        authority: tx-sender,
        criteria-met: criteria-met,
        score: score,
        requested-at: current-block,
        requires-secondary: requires-secondary,
        approved: false,
        rejected: false
      }
    )

    (map-set action-logs
      { action-id: action-id }
      {
        action-type: ACTION_TYPE_ISSUE,
        performer: tx-sender,
        farm-id: farm-id,
        cert-id: u0,
        block-height: current-block
      }
    )
    
    (var-set pending-cert-counter pending-id)
    (var-set action-log-counter action-id)
    (ok pending-id)
  )
)

(define-public (revoke-certification (farm-id uint))
  (let (
    (cert (unwrap! (map-get? certifications { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (action-id (+ (var-get action-log-counter) u1))
  )
    (asserts! (or 
      (is-eq tx-sender (get authority cert))
      (is-eq tx-sender (var-get contract-owner))
    ) ERR_NOT_AUTHORIZED)
    
    (map-set certifications
      { farm-id: farm-id }
      (merge cert { valid: false })
    )
    
    (map-set action-logs
      { action-id: action-id }
      {
        action-type: ACTION_TYPE_REVOKE,
        performer: tx-sender,
        farm-id: farm-id,
        cert-id: (get certification-id cert),
        block-height: burn-block-height
      }
    )
    
    (var-set action-log-counter action-id)
    (ok true)
  )
)

(define-public (approve-certification (pending-id uint))
  (let (
    (pending (unwrap! (map-get? pending-certifications { cert-pending-id: pending-id }) ERR_FARM_NOT_FOUND))
    (farm (unwrap! (map-get? farms { farm-id: (get farm-id pending) }) ERR_FARM_NOT_FOUND))
    (authority (unwrap! (map-get? certification-authorities { authority: (get authority pending) }) ERR_AUTHORITY_NOT_FOUND))
    (current-block burn-block-height)
    (cert-id (+ (var-get total-certifications) u1))
    (action-id (+ (var-get action-log-counter) u1))
  )
    (asserts! (is-supervisor tx-sender) ERR_NOT_SUPERVISOR)
    (asserts! (not (get rejected pending)) ERR_PENDING_APPROVAL)
    (asserts! (not (get approved pending)) ERR_ALREADY_CERTIFIED)
    
    (map-set pending-certifications
      { cert-pending-id: pending-id }
      (merge pending { approved: true })
    )
    
    (if (get requires-secondary pending)
      (map-set secondary-verifications
        { cert-id: cert-id }
        {
          primary-authority: (get authority pending),
          secondary-authority: (var-get contract-owner),
          verified: false,
          verified-at: u0
        }
      )
      true
    )
    
    (map-set certifications
      { farm-id: (get farm-id pending) }
      {
        certification-id: cert-id,
        authority: (get authority pending),
        criteria-met: (get criteria-met pending),
        score: (get score pending),
        issued-at: current-block,
        expires-at: (+ current-block CERTIFICATION_DURATION),
        valid: true
      }
    )
    
    (map-set certification-authorities
      { authority: (get authority pending) }
      (merge authority { certifications-issued: (+ (get certifications-issued authority) u1) })
    )
    
    (map-set action-logs
      { action-id: action-id }
      {
        action-type: ACTION_TYPE_APPROVE,
        performer: tx-sender,
        farm-id: (get farm-id pending),
        cert-id: cert-id,
        block-height: current-block
      }
    )
    
    (var-set total-certifications cert-id)
    (var-set action-log-counter action-id)
    (ok cert-id)
  )
)

(define-public (reject-certification (pending-id uint))
  (let (
    (pending (unwrap! (map-get? pending-certifications { cert-pending-id: pending-id }) ERR_FARM_NOT_FOUND))
    (action-id (+ (var-get action-log-counter) u1))
  )
    (asserts! (is-supervisor tx-sender) ERR_NOT_SUPERVISOR)
    (asserts! (not (get rejected pending)) ERR_ALREADY_CERTIFIED)
    (asserts! (not (get approved pending)) ERR_PENDING_APPROVAL)
    
    (map-set pending-certifications
      { cert-pending-id: pending-id }
      (merge pending { rejected: true })
    )
    
    (map-set action-logs
      { action-id: action-id }
      {
        action-type: ACTION_TYPE_REJECT,
        performer: tx-sender,
        farm-id: (get farm-id pending),
        cert-id: u0,
        block-height: burn-block-height
      }
    )
    
    (var-set action-log-counter action-id)
    (ok true)
  )
)

(define-public (verify-secondary-authority (cert-id uint) (farm-id uint))
  (let (
    (verification (unwrap! (map-get? secondary-verifications { cert-id: cert-id }) ERR_REQUIRES_SECONDARY))
    (authority (unwrap! (map-get? certification-authorities { authority: tx-sender }) ERR_AUTHORITY_NOT_FOUND))
    (cert (unwrap! (map-get? certifications { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (action-id (+ (var-get action-log-counter) u1))
    (current-block burn-block-height)
  )
    (asserts! (is-eq (get certification-id cert) cert-id) ERR_INVALID_CRITERIA)
    (asserts! (not (get verified verification)) ERR_ALREADY_VERIFIED)
    (asserts! (get accredited authority) ERR_NOT_AUTHORIZED)
    (asserts! (not (get suspended authority)) ERR_AUTHORITY_SUSPENDED)
    (asserts! (not (is-eq tx-sender (get primary-authority verification))) ERR_NOT_SECONDARY_AUTHORITY)
    
    (map-set secondary-verifications
      { cert-id: cert-id }
      (merge verification { secondary-authority: tx-sender, verified: true, verified-at: current-block })
    )
    
    (map-set action-logs
      { action-id: action-id }
      {
        action-type: ACTION_TYPE_VERIFY_SECONDARY,
        performer: tx-sender,
        farm-id: farm-id,
        cert-id: cert-id,
        block-height: current-block
      }
    )
    
    (var-set action-log-counter action-id)
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

(define-public (renew-certification (farm-id uint) (criteria-met (list 10 (string-ascii 32))) (score uint))
  (let (
    (farm (unwrap! (map-get? farms { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (existing-cert (unwrap! (map-get? certifications { farm-id: farm-id }) ERR_FARM_NOT_FOUND))
    (authority (unwrap! (map-get? certification-authorities { authority: tx-sender }) ERR_AUTHORITY_NOT_FOUND))
    (current-block burn-block-height)
    (renewal-idx (default-to u0 (get count (map-get? renewal-count { farm-id: farm-id }))))
    (cert-id (+ (var-get total-certifications) u1))
    (discount (if (>= (get score existing-cert) RENEWAL_DISCOUNT_THRESHOLD) RENEWAL_DISCOUNT_RATE u0))
    (renewal-cost (if (> discount u0) (- (var-get certification-fee) (/ (* (var-get certification-fee) discount) u100)) (var-get certification-fee)))
  )
    (asserts! (get accredited authority) ERR_NOT_AUTHORIZED)
    (asserts! (not (get suspended authority)) ERR_AUTHORITY_SUSPENDED)
    (asserts! (get active farm) ERR_FARM_NOT_FOUND)
    (asserts! (<= score u100) ERR_INVALID_CRITERIA)
    (asserts! (>= (get expires-at existing-cert) current-block) ERR_NO_RENEWAL_AVAILABLE)
    
    (map-set certification-history
      { farm-id: farm-id, history-index: renewal-idx }
      {
        certification-id: (get certification-id existing-cert),
        authority: (get authority existing-cert),
        score: (get score existing-cert),
        issued-at: (get issued-at existing-cert),
        expires-at: (get expires-at existing-cert),
        archived-at: current-block
      }
    )
    
    (map-set renewal-count
      { farm-id: farm-id }
      { count: (+ renewal-idx u1) }
    )
    
    (let ((current-cumulative (default-to u0 (get total (map-get? cumulative-score { farm-id: farm-id })))))
      (map-set cumulative-score
        { farm-id: farm-id }
        { total: (+ current-cumulative score) }
      )
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

(define-read-only (get-renewal-count (farm-id uint))
  (default-to u0 (get count (map-get? renewal-count { farm-id: farm-id })))
)

(define-read-only (get-cumulative-score (farm-id uint))
  (default-to u0 (get total (map-get? cumulative-score { farm-id: farm-id })))
)

(define-read-only (get-certification-history (farm-id uint) (history-index uint))
  (map-get? certification-history { farm-id: farm-id, history-index: history-index })
)

(define-read-only (calculate-renewal-cost (farm-id uint))
  (match (map-get? certifications { farm-id: farm-id })
    cert
      (let ((discount (if (>= (get score cert) RENEWAL_DISCOUNT_THRESHOLD) RENEWAL_DISCOUNT_RATE u0)))
        (if (> discount u0)
          (- (var-get certification-fee) (/ (* (var-get certification-fee) discount) u100))
          (var-get certification-fee)
        )
      )
    (var-get certification-fee)
  )
)

(define-read-only (is-supervisor (supervisor principal))
  (match (map-get? supervisors { supervisor: supervisor })
    sup (get active sup)
    false
  )
)

(define-read-only (get-pending-certification (pending-id uint))
  (map-get? pending-certifications { cert-pending-id: pending-id })
)

(define-read-only (get-secondary-verification (cert-id uint))
  (map-get? secondary-verifications { cert-id: cert-id })
)

(define-read-only (get-action-log (action-id uint))
  (map-get? action-logs { action-id: action-id })
)

(define-read-only (is-secondary-verification-required (score uint))
  (>= score SECONDARY_VERIFICATION_THRESHOLD)
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
