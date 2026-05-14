<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>审计查询</h2>
        <p>查询系统操作审计和用户登录审计，仅管理员与审计员可访问。</p>
      </div>
    </div>
    <el-tabs v-model="active" @tab-change="load">
      <el-tab-pane label="操作审计" name="operations">
        <el-form :inline="true" :model="operationFilters" class="toolbar">
          <el-form-item label="操作类型"><el-input v-model="operationFilters.operation_type" clearable /></el-form-item>
          <el-form-item label="用户名"><el-input v-model="operationFilters.username" clearable /></el-form-item>
          <el-form-item label="时间范围">
            <IsoMinuteRangePicker v-model:start="operationFilters.start_time" v-model:end="operationFilters.end_time" />
          </el-form-item>
          <el-button type="primary" :loading="loading" @click="loadOperationsFirstPage">查询</el-button>
          <el-button @click="resetOperations">重置</el-button>
        </el-form>
        <el-table :data="operations.items" v-loading="loading" empty-text="暂无操作审计">
          <el-table-column prop="operation_type" label="操作" min-width="150" />
          <el-table-column prop="username" label="用户" min-width="120" />
          <el-table-column prop="target_type" label="对象类型" min-width="120" />
          <el-table-column label="对象 ID" min-width="220"><template #default="{ row }"><HashText :value="row.target_id" /></template></el-table-column>
          <el-table-column prop="result" label="结果" width="100" />
          <el-table-column prop="occurred_at" label="时间" min-width="190" />
        </el-table>
        <el-pagination
          layout="total, prev, pager, next, sizes"
          :total="operations.total"
          :page-size="operationFilters.size"
          :current-page="operationFilters.page + 1"
          @current-change="handleOperationPageChange"
          @size-change="handleOperationSizeChange"
        />
      </el-tab-pane>
      <el-tab-pane label="登录审计" name="logins">
        <el-form :inline="true" :model="loginFilters" class="toolbar">
          <el-form-item label="用户名"><el-input v-model="loginFilters.username" clearable /></el-form-item>
          <el-form-item label="结果">
            <el-select v-model="loginFilters.success" clearable>
              <el-option label="成功" :value="true" />
              <el-option label="失败" :value="false" />
            </el-select>
          </el-form-item>
          <el-form-item label="时间范围">
            <IsoMinuteRangePicker v-model:start="loginFilters.start_time" v-model:end="loginFilters.end_time" />
          </el-form-item>
          <el-button type="primary" :loading="loading" @click="loadLoginsFirstPage">查询</el-button>
          <el-button @click="resetLogins">重置</el-button>
        </el-form>
        <el-table :data="logins.items" v-loading="loading" empty-text="暂无登录审计">
          <el-table-column prop="username" label="用户" min-width="120" />
          <el-table-column label="结果" width="100">
            <template #default="{ row }">
              <el-tag :type="row.success ? 'success' : 'danger'">{{ row.success ? '成功' : '失败' }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="failure_reason" label="失败原因" min-width="200" />
          <el-table-column prop="client_ip" label="客户端 IP" min-width="130" />
          <el-table-column prop="logged_at" label="时间" min-width="190" />
        </el-table>
        <el-pagination
          layout="total, prev, pager, next, sizes"
          :total="logins.total"
          :page-size="loginFilters.size"
          :current-page="loginFilters.page + 1"
          @current-change="handleLoginPageChange"
          @size-change="handleLoginSizeChange"
        />
      </el-tab-pane>
    </el-tabs>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { listLoginAudits, listOperationAudits } from '../api/backend'
import type { ApiPage, LoginAudit, OperationAudit } from '../api/types'
import HashText from '../components/HashText.vue'
import IsoMinuteRangePicker from '../components/IsoMinuteRangePicker.vue'

const active = ref('operations')
const loading = ref(false)
const operationFilters = reactive({ operation_type: '', username: '', start_time: '', end_time: '', page: 0, size: 20 })
const loginFilters = reactive<{ username: string; success?: boolean; start_time: string; end_time: string; page: number; size: number }>({
  username: '',
  success: undefined,
  start_time: '',
  end_time: '',
  page: 0,
  size: 20
})
const operations = ref<ApiPage<OperationAudit>>({ page: 0, size: 20, total: 0, items: [] })
const logins = ref<ApiPage<LoginAudit>>({ page: 0, size: 20, total: 0, items: [] })

async function loadOperations() {
  loading.value = true
  try {
    operations.value = await listOperationAudits(operationFilters)
  } finally {
    loading.value = false
  }
}

function loadOperationsFirstPage() {
  operationFilters.page = 0
  return loadOperations()
}

async function loadLogins() {
  loading.value = true
  try {
    logins.value = await listLoginAudits(loginFilters)
  } finally {
    loading.value = false
  }
}

function loadLoginsFirstPage() {
  loginFilters.page = 0
  return loadLogins()
}

function resetOperations() {
  operationFilters.operation_type = ''
  operationFilters.username = ''
  operationFilters.start_time = ''
  operationFilters.end_time = ''
  operationFilters.page = 0
  void loadOperations()
}

function resetLogins() {
  loginFilters.username = ''
  loginFilters.success = undefined
  loginFilters.start_time = ''
  loginFilters.end_time = ''
  loginFilters.page = 0
  void loadLogins()
}

function handleOperationPageChange(value: number) {
  operationFilters.page = value - 1
  void loadOperations()
}

function handleOperationSizeChange(value: number) {
  operationFilters.size = value
  operationFilters.page = 0
  void loadOperations()
}

function handleLoginPageChange(value: number) {
  loginFilters.page = value - 1
  void loadLogins()
}

function handleLoginSizeChange(value: number) {
  loginFilters.size = value
  loginFilters.page = 0
  void loadLogins()
}

function load() {
  return active.value === 'operations' ? loadOperations() : loadLogins()
}

onMounted(loadOperations)
</script>
