<template>
  <div class="time-range-picker">
    <el-date-picker
      v-model="startDate"
      class="time-picker-control"
      type="datetime"
      format="YYYY-MM-DD HH:mm"
      placeholder="开始分钟"
      :clearable="true"
    />
    <el-date-picker
      v-model="endDate"
      class="time-picker-control"
      type="datetime"
      format="YYYY-MM-DD HH:mm"
      placeholder="结束分钟"
      :clearable="true"
    />
    <el-button-group class="time-shortcuts">
      <el-button size="small" @click="setCurrentMinute">当前分钟</el-button>
      <el-button size="small" @click="setPreviousMinute">上一分钟</el-button>
      <el-button size="small" @click="setRecentTenMinutes">最近 10 分钟</el-button>
      <el-button size="small" @click="clearRange">清空</el-button>
    </el-button-group>
  </div>
  <div v-if="start || end" class="time-iso-preview">
    UTC {{ start || '-' }} - {{ end || '-' }}
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  start: string
  end: string
}>()

const emit = defineEmits<{
  'update:start': [value: string]
  'update:end': [value: string]
}>()

const startDate = computed<Date | null>({
  get: () => parseIso(props.start),
  set: (value) => emit('update:start', value ? toIsoMinute(value) : '')
})

const endDate = computed<Date | null>({
  get: () => parseIso(props.end),
  set: (value) => emit('update:end', value ? toIsoMinute(value) : '')
})

function parseIso(value: string) {
  if (!value) return null
  const timestamp = Date.parse(value)
  return Number.isNaN(timestamp) ? null : new Date(timestamp)
}

function floorToMinute(value = new Date()) {
  const date = new Date(value)
  date.setSeconds(0, 0)
  return date
}

function addMinutes(value: Date, minutes: number) {
  return new Date(value.getTime() + minutes * 60_000)
}

function toIsoMinute(value: Date) {
  return floorToMinute(value).toISOString()
}

function setRange(start: Date, end: Date) {
  emit('update:start', toIsoMinute(start))
  emit('update:end', toIsoMinute(end))
}

function setCurrentMinute() {
  const start = floorToMinute()
  setRange(start, addMinutes(start, 1))
}

function setPreviousMinute() {
  const end = floorToMinute()
  setRange(addMinutes(end, -1), end)
}

function setRecentTenMinutes() {
  const end = addMinutes(floorToMinute(), 1)
  setRange(addMinutes(end, -10), end)
}

function clearRange() {
  emit('update:start', '')
  emit('update:end', '')
}
</script>
