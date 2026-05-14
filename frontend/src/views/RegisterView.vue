<template>
  <main class="login-page">
    <section class="login-panel">
      <h1>注册账号</h1>
      <el-form :model="form" label-position="top" @submit.prevent="submit">
        <el-form-item label="用户名">
          <el-input v-model="form.username" autocomplete="username" />
        </el-form-item>
        <el-form-item label="显示名称">
          <el-input v-model="form.displayName" autocomplete="name" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" autocomplete="new-password" show-password />
        </el-form-item>
        <el-form-item label="确认密码">
          <el-input v-model="form.confirmPassword" type="password" autocomplete="new-password" show-password />
        </el-form-item>
        <el-button type="primary" :loading="loading" class="full-button" @click="submit">注册</el-button>
      </el-form>
      <div class="auth-links">
        <span>已有账号？</span>
        <el-button link type="primary" @click="$router.push({ name: 'login' })">返回登录</el-button>
      </div>
    </section>
  </main>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { registerUser } from '../api/backend'

const router = useRouter()
const loading = ref(false)
const form = reactive({
  username: '',
  displayName: '',
  password: '',
  confirmPassword: ''
})

async function submit() {
  if (!form.username || !form.displayName || !form.password) {
    ElMessage.warning('请填写完整注册信息')
    return
  }
  if (form.password !== form.confirmPassword) {
    ElMessage.warning('两次输入的密码不一致')
    return
  }
  loading.value = true
  try {
    await registerUser(form.username, form.password, form.displayName)
    ElMessage.success('注册成功，请登录')
    await router.replace({ name: 'login' })
  } finally {
    loading.value = false
  }
}
</script>
