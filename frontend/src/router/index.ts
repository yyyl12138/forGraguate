import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import MainLayout from '../layouts/MainLayout.vue'
import LoginView from '../views/LoginView.vue'
import RegisterView from '../views/RegisterView.vue'
import BatchListView from '../views/BatchListView.vue'
import BatchDetailView from '../views/BatchDetailView.vue'
import LogSearchView from '../views/LogSearchView.vue'
import IntegrityView from '../views/IntegrityView.vue'
import AuditView from '../views/AuditView.vue'
import DataEntryView from '../views/DataEntryView.vue'
import LedgerView from '../views/LedgerView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: LoginView },
    { path: '/register', name: 'register', component: RegisterView },
    {
      path: '/',
      component: MainLayout,
      meta: { requiresAuth: true },
      children: [
        { path: '', redirect: '/batches' },
        { path: 'batches', name: 'batches', component: BatchListView },
        { path: 'batches/:batchId', name: 'batch-detail', component: BatchDetailView, props: true },
        { path: 'logs', name: 'logs', component: LogSearchView },
        { path: 'ledger', name: 'ledger', component: LedgerView },
        { path: 'integrity', name: 'integrity', component: IntegrityView },
        { path: 'audits', name: 'audits', component: AuditView },
        { path: 'data-entry', name: 'data-entry', component: DataEntryView }
      ]
    }
  ]
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (to.meta.requiresAuth) {
    await auth.restoreSession()
    if (!auth.isAuthenticated) {
      return { name: 'login' }
    }
  }
  if ((to.name === 'login' || to.name === 'register') && auth.isAuthenticated) {
    return { name: 'batches' }
  }
  return true
})

export default router
