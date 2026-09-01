import { ChangeEvent, useRef, useState } from 'react'
import { Image as ImageIcon, Trash2, Upload } from 'lucide-react'
import { supabase } from '../lib/supabase'

type MediaKind = 'logo' | 'banner'

type Props = {
  businessId: string
  kind: MediaKind
  value: string
  onChange: (url: string) => void
}

const BUCKET = 'business-assets'
const MAX_FILE_SIZE = 5 * 1024 * 1024
const ALLOWED_TYPES = ['image/png', 'image/jpeg', 'image/webp']

function extensionFor(file: File) {
  if (file.type === 'image/png') return 'png'
  if (file.type === 'image/webp') return 'webp'
  return 'jpg'
}

export function BusinessMediaUpload({ businessId, kind, value, onChange }: Props) {
  const inputRef = useRef<HTMLInputElement | null>(null)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState('')

  const isLogo = kind === 'logo'
  const title = isLogo ? 'Logo da empresa' : 'Banner da empresa'
  const recommendation = isLogo ? '512 × 512 px' : '1600 × 600 px'

  async function handleFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return

    setError('')

    if (!ALLOWED_TYPES.includes(file.type)) {
      setError('Formato inválido. Envie PNG, JPG ou WEBP.')
      return
    }

    if (file.size > MAX_FILE_SIZE) {
      setError('A imagem deve ter no máximo 5 MB.')
      return
    }

    setUploading(true)

    const path = `${businessId}/${kind}-${crypto.randomUUID()}.${extensionFor(file)}`
    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(path, file, {
        cacheControl: '31536000',
        contentType: file.type,
        upsert: false,
      })

    if (uploadError) {
      setUploading(false)
      setError(`Não foi possível enviar a imagem: ${uploadError.message}`)
      return
    }

    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path)
    onChange(data.publicUrl)
    setUploading(false)
  }

  return <div className={`business-media-upload full-span ${isLogo ? 'is-logo' : 'is-banner'}`}>
    <div className="business-media-title"><ImageIcon size={17}/><strong>{title}</strong></div>

    <div className="business-media-preview">
      {value
        ? <img src={value} alt={title}/>
        : <div className="business-media-empty"><ImageIcon size={34}/><span>Nenhuma imagem enviada</span></div>}
    </div>

    <input
      ref={inputRef}
      type="file"
      hidden
      accept="image/png,image/jpeg,image/webp"
      onChange={handleFile}
    />

    <div className="business-media-actions">
      <button
        type="button"
        className="button button-secondary"
        disabled={uploading}
        onClick={() => inputRef.current?.click()}
      >
        <Upload size={16}/>
        {uploading ? 'Enviando...' : value ? 'Trocar imagem' : `Enviar ${isLogo ? 'logo' : 'banner'}`}
      </button>

      {value && <button
        type="button"
        className="button button-secondary"
        disabled={uploading}
        onClick={() => onChange('')}
      >
        <Trash2 size={16}/>Remover
      </button>}
    </div>

    <small className="field-hint">
      PNG, JPG ou WEBP • máximo 5 MB • recomendado: {recommendation}
    </small>
    {error && <small className="business-media-error">{error}</small>}
  </div>
}
