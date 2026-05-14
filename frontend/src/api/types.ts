export type SourceNode = 'node1' | 'node2' | 'node3'
export type UserRole = 'ADMIN' | 'AUDITOR' | 'OPERATOR'
export type UserStatus = 'ACTIVE' | 'DISABLED'

export interface ApiPage<T> {
  page: number
  size: number
  total: number
  items: T[]
}

export interface UserResponse {
  user_id: number
  username: string
  display_name: string
  role: UserRole
  status: UserStatus
}

export interface AuthTokenResponse {
  access_token: string
  refresh_token: string
  token_type: 'Bearer'
  expires_in: number
  user: UserResponse
}

export interface LogRecord {
  log_id: string
  batch_id: string
  source: string
  source_node: SourceNode
  event_time: string
  hostname: string
  app_name: string
  msgid: string
  msg: string
  source_ip: string
  request_method: string
  request_uri: string
  status_code: number | null
  raw_message: string
  normalized_message: Record<string, unknown>
  leaf_hash: string
}

export interface BatchResponse {
  batch_id: string
  source: string
  start_time: string
  end_time: string
  log_count: number
  merkle_root: string
  seal_status: 'SEALED_PENDING_CHAIN' | 'CHAIN_COMMITTED'
  chain_tx_id?: string | null
}

export interface BatchEvidence {
  doc_type?: 'BatchEvidence'
  batch_id: string
  merkle_root: string
  log_count: number
  start_time: string
  end_time: string
  source: string
  schema_version: number
  hash_algorithm: 'SHA-256'
  canonicalization_version: 'clog-v1'
  created_at: string
  tx_id: string
}

export interface BatchDetailResponse {
  ledger_evidence: BatchEvidence
  replica_batches: Record<string, BatchResponse>
  logs: LogRecord[]
}

export type DifferenceType =
  | 'MISSING_LOG'
  | 'EXTRA_LOG'
  | 'MODIFIED_LOG'
  | 'BATCH_ROOT_MISMATCH'
  | 'MULTI_REPLICA_DIVERGENCE'

export interface IntegrityDifference {
  type: DifferenceType
  node: SourceNode
  log_id?: string | null
  node_leaf_hash?: string | null
  reference_leaf_hash?: string | null
  reference_nodes?: SourceNode[]
}

export interface IntegrityCheckResponse {
  batch_id: string
  ledger_root: string
  replica_roots: Record<SourceNode, string>
  abnormal_nodes: SourceNode[]
  differences: IntegrityDifference[]
}

export interface VerifyRootResponse {
  batch_id: string
  expected_merkle_root: string
  actual_merkle_root: string
  matched: boolean
  tx_id: string
}

export interface IngestLogRecord {
  raw_message: string
  file_offset?: number
}

export interface IngestLogsRequest {
  source: string
  hostname: string
  app_name: string
  file_path: string
  records: IngestLogRecord[]
}

export interface IngestLogsResponse {
  accepted_count: number
  failed_count: number
  replica_sync_status: 'PENDING' | 'SYNCED'
  replica_sync_pending_count: number
  logs: Array<{
    log_id: string
    batch_id: string
    event_time: string
    leaf_hash: string
  }>
}

export interface OperationAudit {
  audit_id?: number
  user_id?: number | null
  username?: string | null
  operation_type?: string
  target_type?: string | null
  target_id?: string | null
  result?: string
  client_ip?: string
  user_agent?: string
  detail?: unknown
  occurred_at?: string
}

export interface LoginAudit {
  login_id?: number
  user_id?: number | null
  username?: string
  success?: boolean
  client_ip?: string
  user_agent?: string
  failure_reason?: string | null
  logged_at?: string
}

export interface ProblemDetail {
  title?: string
  detail?: string
  status?: number
}
