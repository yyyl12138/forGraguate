<template>
  <span class="hash-wrap">
    <code class="hash-text" :title="value || undefined">{{ shortValue }}</code>
    <el-button v-if="value" link type="primary" size="small" @click="copy">复制</el-button>
  </span>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { ElMessage } from 'element-plus'

const props = defineProps<{ value?: string | null }>()
const shortValue = computed(() => {
  if (!props.value) return '-'
  return props.value.length > 18 ? `${props.value.slice(0, 12)}...${props.value.slice(-8)}` : props.value
})

async function copy() {
  if (!props.value) return
  const ok = await copyText(props.value)
  if (ok) {
    ElMessage.success('已复制')
  } else {
    ElMessage.error('复制失败，请手动选择文本复制')
  }
}

async function copyText(value: string) {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(value)
      return true
    } catch {
      // HTTP LAN addresses usually reject Clipboard API; fall back below.
    }
  }

  const textarea = document.createElement('textarea')
  textarea.value = value
  textarea.setAttribute('readonly', 'true')
  textarea.style.position = 'fixed'
  textarea.style.left = '-9999px'
  textarea.style.top = '0'
  document.body.appendChild(textarea)
  textarea.focus()
  textarea.select()

  try {
    return document.execCommand('copy')
  } catch {
    return false
  } finally {
    document.body.removeChild(textarea)
  }
}
</script>
