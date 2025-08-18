import './globals.css'
import Providers from './providers'

export const metadata = {
  title: 'Treasure Tiles',
  description: 'Provably fair VRF tiles (Base Sepolia)',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-[#0a0b0f] text-[#d1d5db] antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}
