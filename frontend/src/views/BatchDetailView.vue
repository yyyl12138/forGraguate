<template>
  <section class="page-section">
    <el-button class="back-button" @click="$router.back()">返回</el-button>
    <el-skeleton v-if="loading" :rows="8" animated />
    <template v-else-if="detail">
      <el-descriptions title="链上存证" border :column="2">
        <el-descriptions-item label="批次 ID"><HashText :value="detail.ledger_evidence.batch_id" /></el-descriptions-item>
        <el-descriptions-item label="来源">{{ detail.ledger_evidence.source }}</el-descriptions-item>
        <el-descriptions-item label="Root"><HashText :value="detail.ledger_evidence.merkle_root" /></el-descriptions-item>
        <el-descriptions-item label="交易 ID"><HashText :value="detail.ledger_evidence.tx_id" /></el-descriptions-item>
      </el-descriptions>
      <div class="action-row">
        <el-button type="primary" @click="$router.push({ name: 'integrity', query: { batch_id: detail.ledger_evidence.batch_id } })">执行完整性校验</el-button>
        <el-button @click="$router.push({ name: 'ledger', query: { batch_id: detail.ledger_evidence.batch_id } })">查看账本记录</el-button>
      </div>

      <h2>三库批次元数据</h2>
      <el-table :data="replicaRows" empty-text="暂无副本元数据">
        <el-table-column prop="node" label="节点" width="100" />
        <el-table-column prop="seal_status" label="状态" width="170" />
        <el-table-column prop="log_count" label="日志数" width="90" />
        <el-table-column label="Root" min-width="220">
          <template #default="{ row }"><HashText :value="row.merkle_root" /></template>
        </el-table-column>
        <el-table-column label="链交易" min-width="240">
          <template #default="{ row }"><HashText :value="row.chain_tx_id" /></template>
        </el-table-column>
      </el-table>

      <h2>批次日志</h2>
      <el-table :data="detail.logs" empty-text="暂无日志" height="420">
        <el-table-column label="日志 ID" min-width="230"><template #default="{ row }"><HashText :value="row.log_id" /></template></el-table-column>
        <el-table-column prop="event_time" label="时间" min-width="190" />
        <el-table-column prop="source_ip" label="来源 IP" min-width="130" />
        <el-table-column prop="request_method" label="方法" width="90" />
        <el-table-column prop="request_uri" label="URI" min-width="220" />
        <el-table-column prop="status_code" label="状态码" width="100" />
      </el-table>
    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { getBatch } from '../api/backend'
import type { BatchDetailResponse } from '../api/types'
import HashText from '../components/HashText.vue'

const props = defineProps<{ batchId: string }>()
const loading = ref(false)
const detail = ref<BatchDetailResponse | null>(null)

const replicaRows = computed(() => {
  if (!detail.value) return []
  return Object.entries(detail.value.replica_batches).map(([node, batch]) => ({ node, ...batch }))
})

async function load() {
  loading.value = true
  try {
    detail.value = await getBatch(props.batchId)
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>
