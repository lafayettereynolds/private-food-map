export function splitCompanions(value: string) {
  return [...new Set(value.split(/[,，、/]/).map((item) => item.trim()).filter(Boolean))]
}
