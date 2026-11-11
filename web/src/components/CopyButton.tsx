import { useEffect, useRef, useState } from 'react'
import { IconCheck, IconCopy } from './Icons'

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    // Fallback (http, alte Webviews): verstecktes Textarea + execCommand
    const ta = document.createElement('textarea')
    ta.value = text
    ta.setAttribute('readonly', '')
    ta.style.position = 'fixed'
    ta.style.opacity = '0'
    document.body.appendChild(ta)
    ta.select()
    let ok = false
    try {
      ok = document.execCommand('copy')
    } catch {
      ok = false
    }
    ta.remove()
    return ok
  }
}

interface Props {
  text: string
  label?: string
}

export function CopyButton({ text, label = 'Kopieren' }: Props) {
  const [copied, setCopied] = useState(false)
  const timer = useRef<number | undefined>(undefined)

  useEffect(() => () => window.clearTimeout(timer.current), [])

  const onClick = async () => {
    if (await copyText(text)) {
      setCopied(true)
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(() => setCopied(false), 2000)
    }
  }

  return (
    <button type="button" className={copied ? 'btn-copy ok' : 'btn-copy'} onClick={onClick}>
      {copied ? <IconCheck /> : <IconCopy />}
      <span>{copied ? 'Kopiert' : label}</span>
    </button>
  )
}
