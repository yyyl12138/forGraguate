<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>日志检索</h2>
        <p>按日志字段、时间范围和关键字查询三库日志副本。</p>
      </div>
    </div>
    <el-form :model="filters" class="filter-grid" label-position="top">
      <el-form-item label="副本节点">
        <el-select v-model="filters.source_node" clearable placeholder="默认 node1">
          <el-option label="node1" value="node1" />
          <el-option label="node2" value="node2" />
          <el-option label="node3" value="node3" />
        </el-select>
      </el-form-item>
      <el-form-item label="日志 ID"><el-input v-model="filters.log_id" class="mono-input" clearable /></el-form-item>
      <el-form-item label="批次 ID"><el-input v-model="filters.batch_id" class="mono-input" clearable /></el-form-item>
      <el-form-item label="来源 IP"><el-input v-model="filters.source_ip" clearable /></el-form-item>
      <el-form-item label="URI"><el-input v-model="filters.request_uri" clearable /></el-form-item>
      <el-form-item label="方法">
        <el-select v-model="filters.request_method" clearable placeholder="全部方法">
          <el-option v-for="method in methodOptions" :key="method" :label="method" :value="method" />
        </el-select>
      </el-form-item>
      <el-form-item label="状态码">
        <el-select v-model="filters.status_code" clearable placeholder="全部状态">
          <el-option v-for="code in statusCodeOptions" :key="code" :label="String(code)" :value="code" />
        </el-select>
      </el-form-item>
      <el-form-item label="MsgID">
        <el-select v-model="filters.msgid" clearable placeholder="全部类型">
          <el-option label="WEB_ACCESS - 普通 Web 访问" value="WEB_ACCESS" />
          <el-option label="EXPLOIT_ATTEMPT - 攻击尝试" value="EXPLOIT_ATTEMPT" />
        </el-select>
        <div class="field-hint">WEB_ACCESS 表示普通访问，EXPLOIT_ATTEMPT 表示 PUT 等攻击尝试。</div>
      </el-form-item>
      <el-form-item label="时间范围" class="time-range-form-item">
        <IsoMinuteRangePicker v-model:start="filters.start_time" v-model:end="filters.end_time" />
      </el-form-item>
      <el-form-item label="关键字"><el-input v-model="filters.keyword" clearable /></el-form-item>
    </el-form>
    <div class="action-row compact">
      <el-button type="primary" :loading="loading" @click="loadFirstPage">查询日志</el-button>
      <el-button @click="reset">重置</el-button>
    </div>

    <el-table v-loading="loading" :data="page.items" empty-text="暂无日志数据" height="520">
      <el-table-column label="日志 ID" min-width="230"><template #default="{ row }"><HashText :value="row.log_id" /></template></el-table-column>
      <el-table-column label="批次 ID" min-width="280"><template #default="{ row }"><HashText :value="row.batch_id" /></template></el-table-column>
      <el-table-column prop="source_node" label="节点" width="90" />
      <el-table-column prop="event_time" label="时间" min-width="190" />
      <el-table-column prop="source_ip" label="来源 IP" min-width="130" />
      <el-table-column prop="request_method" label="方法" width="90" />
      <el-table-column prop="request_uri" label="URI" min-width="220" />
      <el-table-column prop="status_code" label="状态码" width="100" />
      <el-table-column label="Leaf" min-width="180"><template #default="{ row }"><HashText :value="row.leaf_hash" /></template></el-table-column>
      <el-table-column label="操作" width="90" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="$router.push({ name: 'batch-detail', params: { batchId: row.batch_id } })">批次</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-pagination
      layout="total, prev, pager, next, sizes"
      :total="page.total"
      :page-size="filters.size"
      :current-page="filters.page + 1"
      @current-change="handlePageChange"
      @size-change="handleSizeChange"
    />
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { searchLogs } from '../api/backend'
import type { ApiPage, LogRecord, SourceNode } from '../api/types'
import HashText from '../components/HashText.vue'
import IsoMinuteRangePicker from '../components/IsoMinuteRangePicker.vue'

const loading = ref(false)
const methodOptions = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS']
const statusCodeOptions = [200, 201, 204, 301, 302, 400, 401, 403, 404, 500]
const filters = reactive<{
  source_node?: SourceNode
  log_id: string
  batch_id: string
  source_ip: string
  request_uri: string
  request_method: string
  status_code?: number
  msgid: string
  start_time: string
  end_time: string
  keyword: string
  page: number
  size: number
}>({
  source_node: undefined,
  log_id: '',
  batch_id: '',
  source_ip: '',
  request_uri: '',
  request_method: '',
  status_code: undefined,
  msgid: '',
  start_time: '',
  end_time: '',
  keyword: '',
  page: 0,
  size: 50
})
const page = ref<ApiPage<LogRecord>>({ page: 0, size: 50, total: 0, items: [] })

async function load() {
  loading.value = true
  try {
    page.value = await searchLogs(filters)
  } finally {
    loading.value = false
  }
}

function loadFirstPage() {
  filters.page = 0
  return load()
}

function reset() {
  filters.source_node = undefined
  filters.log_id = ''
  filters.batch_id = ''
  filters.source_ip = ''
  filters.request_uri = ''
  filters.request_method = ''
  filters.status_code = undefined
  filters.msgid = ''
  filters.start_time = ''
  filters.end_time = ''
  filters.keyword = ''
  filters.page = 0
  page.value = { page: 0, size: filters.size, total: 0, items: [] }
}

function handlePageChange(value: number) {
  filters.page = value - 1
  void load()
}

function handleSizeChange(value: number) {
  filters.size = value
  filters.page = 0
  void load()
}
</script>
