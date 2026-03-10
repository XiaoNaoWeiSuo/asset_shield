param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

& dart run asset_shield @Args
