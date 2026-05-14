import { defineStore } from 'pinia'
import { currentUser, login, logout, refreshToken as refreshAuthToken } from '../api/backend'
import type { UserResponse } from '../api/types'

interface AuthState {
  accessToken: string
  refreshToken: string
  user: UserResponse | null
}

const ACCESS_KEY = 'logtrace_access_token'
const REFRESH_KEY = 'logtrace_refresh_token'

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    accessToken: localStorage.getItem(ACCESS_KEY) || '',
    refreshToken: localStorage.getItem(REFRESH_KEY) || '',
    user: null
  }),
  getters: {
    isAuthenticated: (state) => Boolean(state.accessToken)
  },
  actions: {
    async login(username: string, password: string) {
      const response = await login(username, password)
      this.accessToken = response.access_token
      this.refreshToken = response.refresh_token
      this.user = response.user
      localStorage.setItem(ACCESS_KEY, this.accessToken)
      localStorage.setItem(REFRESH_KEY, this.refreshToken)
    },
    async restoreSession() {
      if ((!this.accessToken && !this.refreshToken) || this.user) return
      const savedRefreshToken = this.refreshToken
      try {
        if (this.accessToken) {
          this.user = await currentUser()
          return
        }
      } catch {
        // Fall through to refresh token recovery.
      }
      if (!savedRefreshToken) {
        this.clearSession()
        return
      }
      try {
        const response = await refreshAuthToken(savedRefreshToken)
        this.accessToken = response.access_token
        this.refreshToken = response.refresh_token
        this.user = response.user
        localStorage.setItem(ACCESS_KEY, this.accessToken)
        localStorage.setItem(REFRESH_KEY, this.refreshToken)
      } catch {
        this.clearSession()
      }
    },
    async logout() {
      try {
        await logout(this.refreshToken)
      } finally {
        this.clearSession()
      }
    },
    clearSession() {
      this.accessToken = ''
      this.refreshToken = ''
      this.user = null
      localStorage.removeItem(ACCESS_KEY)
      localStorage.removeItem(REFRESH_KEY)
    }
  }
})
