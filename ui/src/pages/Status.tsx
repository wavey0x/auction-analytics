import React, { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ChevronRight, ChevronDown } from 'lucide-react'
import { apiClient } from '../lib/api'

type ServiceItem = {
  name: string
  status: 'ok' | 'degraded' | 'down' | 'unknown'
  detail?: string
  metrics?: Record<string, any>
}

const Dot: React.FC<{ status: string }> = ({ status }) => {
  const color = status === 'ok' ? 'bg-green-500' : status === 'degraded' ? 'bg-yellow-500' : status === 'down' ? 'bg-red-500' : 'bg-gray-500'
  return <span className={`inline-block h-2.5 w-2.5 rounded-full ${color}`} />
}

const ServiceRow: React.FC<{ service: ServiceItem }> = ({ service }) => {
  const [isExpanded, setIsExpanded] = useState(false)
  
  // Derive UI status: treat Prices as green when pending == 0
  const displayStatus = React.useMemo(() => {
    if (service?.name === 'prices') {
      const pending = (service.metrics as any)?.pending
      if (pending === 0) return 'ok'
    }
    return service.status
  }, [service])

  const hasMetrics = service.metrics && Object.keys(service.metrics).length > 0

  return (
    <div className="border-b border-gray-800/70 last:border-0">
      <div 
        className="flex items-center justify-between py-2 cursor-pointer hover:bg-gray-800/20 transition-colors"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <div className="flex items-center gap-2">
          <Dot status={displayStatus} />
          <span className="text-sm text-gray-200 font-medium capitalize">{service.name}</span>
          <span className="text-xs text-gray-400">{service.detail}</span>
        </div>
        <div className="flex items-center gap-3">
          {!isExpanded && hasMetrics && (
            <div className="text-xs text-gray-400 flex items-center gap-3">
              {Object.entries(service.metrics).slice(0, 4).map(([k, v]) => (
                <span key={k} className="font-mono">
                  {k}:{' '}
                  {typeof v === 'object' ? '-' : String(v)}
                </span>
              ))}
            </div>
          )}
          {hasMetrics && (
            isExpanded ? 
              <ChevronDown className="h-4 w-4 text-gray-400" /> : 
              <ChevronRight className="h-4 w-4 text-gray-400" />
          )}
        </div>
      </div>
      
      {isExpanded && hasMetrics && (
        <div className="px-6 pb-3">
          <div className="text-xs text-gray-500 mb-2">All Metrics</div>
          <div className="grid grid-cols-2 gap-2">
            {Object.entries(service.metrics).map(([k, v]) => (
              <div key={k} className="bg-gray-800/30 p-2 rounded text-xs">
                <div className="text-gray-400 capitalize">{k.replace(/_/g, ' ')}</div>
                <div className="text-gray-200 font-mono">
                  {typeof v === 'object' ? JSON.stringify(v, null, 2) : String(v)}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

const StatusPage: React.FC = () => {
  const { data, isLoading, error } = useQuery({
    queryKey: ['status'],
    queryFn: () => apiClient.getStatus(),
    refetchInterval: 15000,
    staleTime: 10000,
  })

  return (
    <div className="space-y-6">
      <div className="card">
        <div className="card-header">System Status</div>
        <div className="card-body">
          {isLoading && <div className="text-sm text-gray-400">Loading status…</div>}
          {error && <div className="text-sm text-red-400">Failed to load status</div>}
          {data && (
            <>
              <div className="text-xs text-gray-500 mb-2">
                Updated at {new Date((data.generated_at || 0) * 1000).toLocaleTimeString()}
              </div>
              <div className="divide-y divide-gray-800/70">
                {data.services?.map((service: ServiceItem) => (
                  <ServiceRow key={service.name} service={service} />
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default StatusPage