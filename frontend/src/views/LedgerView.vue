<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>账本存证</h2>
        <p>查询 Fabric 链上的批次存证锚点；数据库重算 Root 与三库差异定位请进入完整性校验。</p>
      </div>
    </div>

    <el-form :inline="true" :model="queryForm" class="toolbar">
      <el-form-item label="来源">
        <el-input v-model="queryForm.source" placeholder="tomcat-cve-2017-12615" clearable />
      </el-form-item>
      <el-form-item label="时间范围">
        <IsoMinuteRangePicker v-model:start="queryForm.start_time" v-model:end="queryForm.end_time" />
      </el-form-item>
      <el-button type="primary" :loading="loading" @click="loadList">查询</el-button>
      <el-button @click="resetQuery">重置</el-button>
    </el-form>

    <el-table v-loading="loading" :data="records" empty-text="暂无账本记录">
      <el-table-column prop="batch_id" label="批次 ID" min-width="280" />
      <el-table-column prop="source" label="来源" min-width="180" />
      <el-table-column prop="start_time" label="开始时间" min-width="190" />
      <el-table-column prop="log_count" label="日志数" width="90" />
      <el-table-column label="Root" min-width="220">
        <template #default="{ row }"><HashText :value="row.merkle_root" /></template>
      </el-table-column>
      <el-table-column label="操作" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="loadDetail(row.batch_id)">详情</el-button>
          <el-button link type="primary" @click="openIntegrity(row.batch_id)">完整性</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-alert
      class="detail-block"
      type="info"
      title="Root 校验边界"
      description="账本接口只能证明提交的候选 Root 是否等于链上 Root，不会读取 MySQL。正式演示中的篡改检测应使用完整性校验，它会从三库重算 Root 并与链上存证对比。"
      :closable="false"
      show-icon
    />

    <h2>按批次查询</h2>
    <el-form :inline="true" :model="detailForm" class="toolbar">
      <el-form-item label="批次 ID">
        <el-input v-model="detailForm.batch_id" class="wide-input" clearable />
      </el-form-item>
      <el-button type="primary" :loading="detailLoading" @click="loadDetail(detailForm.batch_id)">查询详情</el-button>
      <el-button @click="resetDetail">重置</el-button>
    </el-form>

    <el-descriptions v-if="detail" border :column="2" class="detail-block">
      <el-descriptions-item label="批次 ID"><HashText :value="detail.batch_id" /></el-descriptions-item>
      <el-descriptions-item label="来源">{{ detail.source }}</el-descriptions-item>
      <el-descriptions-item label="Root"><HashText :value="detail.merkle_root" /></el-descriptions-item>
      <el-descriptions-item label="交易 ID"><HashText :value="detail.tx_id" /></el-descriptions-item>
      <el-descriptions-item label="时间窗">{{ detail.start_time }} - {{ detail.end_time }}</el-descriptions-item>
      <el-descriptions-item label="算法">{{ detail.hash_algorithm }} / {{ detail.canonicalization_version }}</el-descriptions-item>
    </el-descriptions>
    <div v-if="detail" class="action-row compact">
      <el-button type="primary" @click="openIntegrity(detail.batch_id)">执行数据库完整性校验</el-button>
      <el-button @click="$router.push({ name: 'batch-detail', params: { batchId: detail.batch_id } })">查看批次详情</el-button>
    </div>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getLedgerBatch, listLedgerBatches } from '../api/backend'
import type { BatchEvidence } from '../api/types'
import HashText from '../components/HashText.vue'
import IsoMinuteRangePicker from '../components/IsoMinuteRangePicker.vue'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const detailLoading = ref(false)
const records = ref<BatchEvidence[]>([])
const detail = ref<BatchEvidence | null>(null)

const queryForm = reactive({ source: '', start_time: '', end_time: '' })
const detailForm = reactive({ batch_id: '' })

async function loadList() {
  loading.value = true
  try {
    records.value = await listLedgerBatches(queryForm)
  } finally {
    loading.value = false
  }
}

function resetQuery() {
  queryForm.source = ''
  queryForm.start_time = ''
  queryForm.end_time = ''
  records.value = []
}

function resetDetail() {
  detailForm.batch_id = ''
  detail.value = null
}

async function loadDetail(batchId: string) {
  if (!batchId) return
  detailLoading.value = true
  try {
    detail.value = await getLedgerBatch(batchId)
    detailForm.batch_id = batchId
  } finally {
    detailLoading.value = false
  }
}

function openIntegrity(batchId: string) {
  if (!batchId) return
  void router.push({ name: 'integrity', query: { batch_id: batchId } })
}

onMounted(() => {
  const batchId = typeof route.query.batch_id === 'string' ? route.query.batch_id : ''
  if (batchId) {
    detailForm.batch_id = batchId
    void loadDetail(batchId)
  } else {
    void loadList()
  }
})
</script>
