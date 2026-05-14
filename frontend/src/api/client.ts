import { ElMessage } from 'element-plus'
import router from '../router'
import { useAuthStore } from '../stores/auth'
import type { ProblemDetail } from './types'

const apiBase = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '')

export class ApiError extends Error {
  status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

export async function apiRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const auth = useAuthStore()
  const headers = new Headers(options.headers)
  if (!headers.has('Content-Type') && options.body) {
    headers.set('Content-Type', 'application/json')
  }
  if (auth.accessToken) {
    headers.set('Authorization', `Bearer ${auth.accessToken}`)
  }

  const response = await fetch(`${apiBase}${path}`, {
    ...options,
    headers
  })

  if (response.status === 204) {
    return undefined as T
  }

  if (!response.ok) {
    let message = `HTTP ${response.status}`
    try {
      const problem = (await response.json()) as ProblemDetail
      message = problem.detail || problem.title || message
    } catch {
      message = response.statusText || message
    }
    if (response.status === 401) {
      auth.clearSession()
      await router.replace({ name: 'login' })
    }
    ElMessage.error(message)
    throw new ApiError(response.status, message)
  }

  return (await response.json()) as T
}

export function toQuery(params: Record<string, string | number | boolean | null | undefined>) {
  const query = new URLSearchParams()
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      query.set(key, String(value))
    }
  })
  const value = query.toString()
  return value ? `?${value}` : ''
}
