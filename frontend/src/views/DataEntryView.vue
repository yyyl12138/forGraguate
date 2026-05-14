<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>备用手工工具</h2>
        <p>该页面保留给排障和手工接口验证，正式阶段 12 演示使用 VM 流量脚本生成批次。</p>
      </div>
    </div>
    <el-alert title="该页面已从主导航隐藏；它只调用真实后端接口，不生成前端 mock 数据，也不提供数据库篡改入口。" type="info" :closable="false" />
    <h2>接收日志</h2>
    <el-form :model="ingestForm" label-position="top" class="data-form">
      <el-form-item label="来源"><el-input v-model="ingestForm.source" /></el-form-item>
      <el-form-item label="主机名"><el-input v-model="ingestForm.hostname" /></el-form-item>
      <el-form-item label="应用名"><el-input v-model="ingestForm.app_name" /></el-form-item>
      <el-form-item label="文件路径"><el-input v-model="ingestForm.file_path" /></el-form-item>
      <el-form-item label="日志行">
        <el-input v-model="rawLines" type="textarea" :rows="6" placeholder="每行一条 Tomcat access log" />
      </el-form-item>
      <div class="action-row compact">
        <el-button type="primary" :loading="ingesting" @click="submitIngest">提交日志</el-button>
        <el-button @click="resetIngest">重置</el-button>
      </div>
    </el-form>
    <el-alert
      v-if="ingestSyncSummary"
      :title="ingestSyncSummary"
      type="success"
      :closable="false"
      class="detail-block"
    />
    <el-table v-if="ingestResult.length" :data="ingestResult" class="detail-block" empty-text="暂无接收结果">
      <el-table-column label="日志 ID" min-width="240"><template #default="{ row }"><HashText :value="row.log_id" /></template></el-table-column>
      <el-table-column label="批次 ID" min-width="280"><template #default="{ row }"><HashText :value="row.batch_id" /></template></el-table-column>
      <el-table-column prop="event_time" label="时间" min-width="190" />
      <el-table-column label="Leaf" min-width="220"><template #default="{ row }"><HashText :value="row.leaf_hash" /></template></el-table-column>
    </el-table>

    <h2>封存批次</h2>
    <el-form :inline="true" :model="sealForm" class="toolbar">
      <el-form-item label="来源"><el-input v-model="sealForm.source" /></el-form-item>
      <el-form-item label="窗口开始"><el-input v-model="sealForm.start_time" class="wide-input" placeholder="2026-04-22T02:05:00.000Z" /></el-form-item>
      <el-button type="primary" :loading="sealing" @click="submitSeal">封存</el-button>
      <el-button @click="resetSeal">重置</el-button>
    </el-form>
    <el-descriptions v-if="sealResult" border :column="2" class="detail-block">
      <el-descriptions-item label="批次 ID"><HashText :value="sealResult.batch_id" /></el-descriptions-item>
      <el-descriptions-item label="来源">{{ sealResult.source }}</el-descriptions-item>
      <el-descriptions-item label="Root"><HashText :value="sealResult.merkle_root" /></el-descriptions-item>
      <el-descriptions-item label="状态">{{ sealResult.seal_status }}</el-descriptions-item>
      <el-descriptions-item label="日志数">{{ sealResult.log_count }}</el-descriptions-item>
      <el-descriptions-item label="交易 ID"><HashText :value="sealResult.chain_tx_id" /></el-descriptions-item>
    </el-descriptions>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { ingestLogs, sealBatch } from '../api/backend'
import type { BatchResponse, IngestLogsResponse } from '../api/types'
import HashText from '../components/HashText.vue'

const ingesting = ref(false)
const sealing = ref(false)
const rawLines = ref('172.18.0.1 - - [22/Apr/2026:10:05:01 +0800] "GET / HTTP/1.1" 200 11230')
const ingestResult = ref<IngestLogsResponse['logs']>([])
const ingestSyncSummary = ref('')
const sealResult = ref<BatchResponse | null>(null)
const ingestForm = reactive({
  source: 'tomcat-cve-2017-12615',
  hostname: 'node1',
  app_name: 'tomcat',
  file_path: '/opt/log-trace/vulhub-logs/tomcat/localhost_access_log.2026-04-22.txt'
})
const sealForm = reactive({
  source: 'tomcat-cve-2017-12615',
  start_time: '2026-04-22T02:05:00.000Z'
})

async function submitIngest() {
  ingesting.value = true
  try {
    const lines = rawLines.value.split('\n').map((line) => line.trim()).filter(Boolean)
    const response = await ingestLogs({
      ...ingestForm,
      records: lines.map((line, index) => ({ raw_message: line, file_offset: index * 82 }))
    })
    ingestResult.value = response.logs
    ingestSyncSummary.value = `${response.replica_sync_status} / pending ${response.replica_sync_pending_count}`
    ElMessage.success(`已接收 ${response.accepted_count} 条日志，副本同步待处理 ${response.replica_sync_pending_count} 项`)
  } finally {
    ingesting.value = false
  }
}

async function submitSeal() {
  sealing.value = true
  try {
    const response = await sealBatch(sealForm.source, sealForm.start_time)
    sealResult.value = response
    ElMessage.success(`批次已封存：${response.batch_id}`)
  } finally {
    sealing.value = false
  }
}

function resetIngest() {
  rawLines.value = ''
  ingestResult.value = []
  ingestSyncSummary.value = ''
}

function resetSeal() {
  sealForm.source = 'tomcat-cve-2017-12615'
  sealForm.start_time = '2026-04-22T02:05:00.000Z'
  sealResult.value = null
}
</script>
