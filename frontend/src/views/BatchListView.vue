<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>批次管理</h2>
        <p>查看本地批次元数据，并进入详情或完整性校验。</p>
      </div>
      <el-button :loading="loading" @click="load">刷新</el-button>
    </div>
    <el-form :inline="true" :model="filters" class="toolbar">
      <el-form-item label="来源">
        <el-input v-model="filters.source" placeholder="tomcat-cve-2017-12615" clearable />
      </el-form-item>
      <el-form-item label="时间范围">
        <IsoMinuteRangePicker v-model:start="filters.start_time" v-model:end="filters.end_time" />
      </el-form-item>
      <el-button type="primary" :loading="loading" @click="load">查询</el-button>
      <el-button @click="reset">重置</el-button>
    </el-form>

    <el-table v-loading="loading" :data="page.items" empty-text="暂无批次数据">
      <el-table-column label="批次 ID" min-width="280"><template #default="{ row }"><HashText :value="row.batch_id" /></template></el-table-column>
      <el-table-column prop="source" label="来源" min-width="180" />
      <el-table-column prop="start_time" label="开始时间" min-width="190" />
      <el-table-column prop="log_count" label="日志数" width="90" />
      <el-table-column label="Root" min-width="190">
        <template #default="{ row }"><HashText :value="row.merkle_root" /></template>
      </el-table-column>
      <el-table-column label="状态" width="150">
        <template #default="{ row }">
          <el-tag :type="row.seal_status === 'CHAIN_COMMITTED' ? 'success' : 'warning'">{{ row.seal_status }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="250">
        <template #default="{ row }">
          <el-button link type="primary" @click="$router.push({ name: 'batch-detail', params: { batchId: row.batch_id } })">详情</el-button>
          <el-button link type="primary" @click="$router.push({ name: 'integrity', query: { batch_id: row.batch_id } })">校验</el-button>
          <el-button link type="primary" @click="$router.push({ name: 'ledger', query: { batch_id: row.batch_id } })">账本</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-pagination
      layout="total, prev, pager, next, sizes"
      :total="page.total"
      :page-size="filters.size"
      :current-page="filters.page + 1"
      @current-change="(value: number) => { filters.page = value - 1; load() }"
      @size-change="(value: number) => { filters.size = value; filters.page = 0; load() }"
    />
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { listBatches } from '../api/backend'
import type { ApiPage, BatchResponse } from '../api/types'
import HashText from '../components/HashText.vue'
import IsoMinuteRangePicker from '../components/IsoMinuteRangePicker.vue'

const loading = ref(false)
const filters = reactive({ source: '', start_time: '', end_time: '', page: 0, size: 20 })
const page = ref<ApiPage<BatchResponse>>({ page: 0, size: 20, total: 0, items: [] })

async function load() {
  loading.value = true
  try {
    page.value = await listBatches(filters)
  } finally {
    loading.value = false
  }
}

function reset() {
  filters.source = ''
  filters.start_time = ''
  filters.end_time = ''
  filters.page = 0
  load()
}

onMounted(load)
</script>
