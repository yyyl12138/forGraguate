import { apiRequest, toQuery } from './client'
import type {
  ApiPage,
  AuthTokenResponse,
  BatchEvidence,
  BatchDetailResponse,
  BatchResponse,
  IngestLogsRequest,
  IngestLogsResponse,
  IntegrityCheckResponse,
  LogRecord,
  LoginAudit,
  OperationAudit,
  SourceNode,
  UserResponse,
  VerifyRootResponse
} from './types'

export function login(username: string, password: string) {
  return apiRequest<AuthTokenResponse>('/api/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password })
  })
}

export function refreshToken(refreshToken: string) {
  return apiRequest<AuthTokenResponse>('/api/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: refreshToken })
  })
}

export function registerUser(username: string, password: string, displayName: string) {
  return apiRequest<UserResponse>('/api/auth/register', {
    method: 'POST',
    body: JSON.stringify({ username, password, display_name: displayName })
  })
}

export function logout(refreshToken?: string) {
  return apiRequest<void>('/api/auth/logout', {
    method: 'POST',
    body: refreshToken ? JSON.stringify({ refresh_token: refreshToken }) : undefined
  })
}

export function currentUser() {
  return apiRequest<UserResponse>('/api/auth/me')
}

export function listBatches(params: {
  source?: string
  start_time?: string
  end_time?: string
  page: number
  size: number
}) {
  return apiRequest<ApiPage<BatchResponse>>(`/api/batches${toQuery(params)}`)
}

export function getBatch(batchId: string) {
  return apiRequest<BatchDetailResponse>(`/api/batches/${encodeURIComponent(batchId)}`)
}

export function listLedgerBatches(params: {
  source?: string
  start_time?: string
  end_time?: string
}) {
  return apiRequest<BatchEvidence[]>(`/api/ledger/batches${toQuery(params)}`)
}

export function getLedgerBatch(batchId: string) {
  return apiRequest<BatchEvidence>(`/api/ledger/batches/${encodeURIComponent(batchId)}`)
}

export function verifyLedgerRoot(batchId: string, merkleRoot: string) {
  return apiRequest<VerifyRootResponse>(`/api/ledger/batches/${encodeURIComponent(batchId)}/verify-root`, {
    method: 'POST',
    body: JSON.stringify({ merkle_root: merkleRoot })
  })
}

export function sealBatch(source: string, startTime: string) {
  return apiRequest<BatchResponse>('/api/batches/seal', {
    method: 'POST',
    body: JSON.stringify({ source, start_time: startTime })
  })
}

export function searchLogs(params: {
  source_node?: SourceNode
  log_id?: string
  batch_id?: string
  source_ip?: string
  request_uri?: string
  request_method?: string
  status_code?: number
  msgid?: string
  start_time?: string
  end_time?: string
  keyword?: string
  page: number
  size: number
}) {
  return apiRequest<ApiPage<LogRecord>>(`/api/logs/search${toQuery(params)}`)
}

export function ingestLogs(payload: IngestLogsRequest) {
  return apiRequest<IngestLogsResponse>('/api/logs/ingest', {
    method: 'POST',
    body: JSON.stringify(payload)
  })
}

export function checkIntegrity(batchId: string) {
  return apiRequest<IntegrityCheckResponse>('/api/integrity/check', {
    method: 'POST',
    body: JSON.stringify({ batch_id: batchId })
  })
}

export function listOperationAudits(params: {
  operation_type?: string
  username?: string
  start_time?: string
  end_time?: string
  page: number
  size: number
}) {
  return apiRequest<ApiPage<OperationAudit>>(`/api/audits/operations${toQuery(params)}`)
}

export function listLoginAudits(params: {
  username?: string
  success?: boolean
  start_time?: string
  end_time?: string
  page: number
  size: number
}) {
  return apiRequest<ApiPage<LoginAudit>>(`/api/audits/logins${toQuery(params)}`)
}
