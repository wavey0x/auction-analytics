import React from 'react'

type AppLogoProps = {
  className?: string
  accent?: string
  text?: string
  title?: string
  iconPx?: number
}

// Image-based logo lockup using the generated square logo in /public
const AppLogo: React.FC<AppLogoProps> = ({
  className,
  accent = '#58aaff',
  text = '#cfe3ff',
  title = 'AuctionExplorer',
  iconPx = 56,
}) => {
  const wrapCls = `inline-flex items-center gap-0 leading-none ${className || ''}`

  return (
    <div className={wrapCls} role="img" aria-label={title}>
      {/* Text-only wordmark for a compact header */}
      <span
        className="font-mono font-extrabold uppercase tracking-[0.08em] whitespace-nowrap select-none"
        style={{ fontSize: '1.44em', lineHeight: 1 }}
      >
        <span style={{ color: accent }} className="mr-2">AUCTION</span>
        <span style={{ color: text }} className="font-bold">EXPLORER</span>
      </span>
    </div>
  )
}

export default AppLogo
