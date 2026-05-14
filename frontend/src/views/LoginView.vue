<template>
  <main class="login-page">
    <section class="login-panel">
      <h1>Log Traceability</h1>
      <el-form :model="form" label-position="top" @submit.prevent="submit">
        <el-form-item label="用户名">
          <el-input v-model="form.username" autocomplete="username" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" autocomplete="current-password" show-password />
        </el-form-item>
        <el-button type="primary" :loading="loading" class="full-button" @click="submit">登录</el-button>
      </el-form>
      <div class="auth-links">
        <span>没有账号？</span>
        <el-button link type="primary" @click="$router.push({ name: 'register' })">注册</el-button>
      </div>
    </section>
  </main>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const router = useRouter()
const loading = ref(false)
const form = reactive({ username: '', password: '' })

async function submit() {
  loading.value = true
  try {
    await auth.login(form.username, form.password)
    await router.replace({ name: 'batches' })
  } finally {
    loading.value = false
  }
}
</script>
