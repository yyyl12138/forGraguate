<template>
  <el-container class="app-shell">
    <el-aside width="240px" class="sidebar">
      <div class="brand">Log Traceability</div>
      <el-menu router :default-active="$route.path" class="menu">
        <el-menu-item index="/batches">批次管理</el-menu-item>
        <el-menu-item index="/ledger">账本存证</el-menu-item>
        <el-menu-item index="/logs">日志检索</el-menu-item>
        <el-menu-item index="/integrity">完整性校验</el-menu-item>
        <el-menu-item index="/audits">审计查询</el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="topbar">
        <div class="topbar-title">{{ routeTitle }}</div>
        <div class="user-block">
          <span>{{ auth.user?.display_name || auth.user?.username }}</span>
          <el-tag size="small">{{ auth.user?.role }}</el-tag>
          <el-button size="small" @click="handleLogout">退出</el-button>
        </div>
      </el-header>
      <el-main class="content">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const titles: Record<string, string> = {
  '/batches': '批次列表',
  '/ledger': '账本存证',
  '/logs': '日志检索',
  '/integrity': '完整性校验',
  '/audits': '审计查询',
  '/data-entry': '数据录入'
}

const routeTitle = computed(() => titles[route.path] || '批次详情')

async function handleLogout() {
  await auth.logout()
  await router.replace({ name: 'login' })
}
</script>
