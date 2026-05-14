<template>
  <section class="page-section">
    <div class="section-head">
      <div>
        <h2>完整性校验</h2>
        <p>按批次读取链上 Root 与三库日志，定位异常副本和差异类型。</p>
      </div>
    </div>
    <el-form :inline="true" :model="form" class="toolbar">
      <el-form-item label="批次 ID"><el-input v-model="form.batch_id" class="wide-input" clearable /></el-form-item>
      <el-button type="primary" :loading="loading" @click="check">执行校验</el-button>
      <el-button @click="reset">重置</el-button>
    </el-form>

    <template v-if="result">
      <el-alert
        :type="result.abnormal_nodes.length ? 'error' : 'success'"
        :title="result.abnormal_nodes.length ? `发现异常节点：${result.abnormal_nodes.join(', ')}` : '三库 Root 与链上 Root 一致'"
        show-icon
        :closable="false"
      />
      <h2>Root 对比</h2>
      <el-table :data="rootRows">
        <el-table-column prop="node" label="节点" width="100" />
        <el-table-column label="链上 Root" min-width="220"><template #default><HashText :value="result?.ledger_root" /></template></el-table-column>
        <el-table-column label="Root" min-width="220"><template #default="{ row }"><HashText :value="row.root" /></template></el-table-column>
        <el-table-column label="状态" width="120"><template #default="{ row }"><el-tag :type="row.root === result?.ledger_root ? 'success' : 'danger'">{{ row.root === result?.ledger_root ? '一致' : '异常' }}</el-tag></template></el-table-column>
      </el-table>

      <h2>差异定位</h2>
      <el-table :data="result.differences" empty-text="无差异">
        <el-table-column prop="type" label="类型" min-width="190" />
        <el-table-column prop="node" label="节点" width="100" />
        <el-table-column prop="log_id" label="日志 ID" min-width="230" />
        <el-table-column label="节点 Leaf" min-width="180"><template #default="{ row }"><HashText :value="row.node_leaf_hash" /></template></el-table-column>
        <el-table-column label="参考 Leaf" min-width="180"><template #default="{ row }"><HashText :value="row.reference_leaf_hash" /></template></el-table-column>
        <el-table-column label="参考节点" min-width="140">
          <template #default="{ row }">{{ row.reference_nodes?.join(', ') || '-' }}</template>
        </el-table-column>
      </el-table>
    </template>
    <el-empty v-else description="输入批次 ID 后执行校验" />
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import { checkIntegrity } from '../api/backend'
import type { IntegrityCheckResponse } from '../api/types'
import HashText from '../components/HashText.vue'

const route = useRoute()
const loading = ref(false)
const form = reactive({ batch_id: '' })
const result = ref<IntegrityCheckResponse | null>(null)
const rootRows = computed(() => {
  if (!result.value) return []
  return Object.entries(result.value.replica_roots).map(([node, root]) => ({ node, root }))
})

async function check() {
  if (!form.batch_id) return
  loading.value = true
  try {
    result.value = await checkIntegrity(form.batch_id)
  } finally {
    loading.value = false
  }
}

function reset() {
  form.batch_id = ''
  result.value = null
}

onMounted(() => {
  const batchId = typeof route.query.batch_id === 'string' ? route.query.batch_id : ''
  if (batchId) {
    form.batch_id = batchId
    void check()
  }
})
</script>
