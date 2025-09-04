/**
 * RPC Health Monitor - Tracks RPC call success/failure rates and performance
 */

export interface RPCCallResult {
  chainId: number
  success: boolean
  duration: number // milliseconds
  error?: string
  timestamp: number
}

export interface ChainHealth {
  chainId: number
  successRate: number // 0-1
  averageLatency: number // milliseconds
  totalCalls: number
  failedCalls: number
  lastSuccess: number | null
  lastFailure: number | null
  status: 'healthy' | 'degraded' | 'down' | 'unknown'
}

export interface RPCHealthSummary {
  overallStatus: 'healthy' | 'degraded' | 'down'
  totalChains: number
  healthyChains: number
  degradedChains: number
  downChains: number
  chains: ChainHealth[]
  lastUpdate: number
}

class RPCHealthMonitor {
  private callHistory: Map<number, RPCCallResult[]> = new Map()
  private readonly HISTORY_WINDOW = 5 * 60 * 1000 // 5 minutes
  private readonly MAX_CALLS_PER_CHAIN = 100 // Keep last 100 calls per chain

  /**
   * Record the result of an RPC call
   */
  recordCall(result: RPCCallResult): void {
    const { chainId } = result
    
    if (!this.callHistory.has(chainId)) {
      this.callHistory.set(chainId, [])
    }

    const calls = this.callHistory.get(chainId)!
    calls.unshift(result) // Add to beginning

    // Keep only recent calls and limit total calls per chain
    const cutoff = Date.now() - this.HISTORY_WINDOW
    this.callHistory.set(
      chainId,
      calls
        .filter(call => call.timestamp > cutoff)
        .slice(0, this.MAX_CALLS_PER_CHAIN)
    )
  }

  /**
   * Get health status for a specific chain
   */
  getChainHealth(chainId: number): ChainHealth {
    const calls = this.callHistory.get(chainId) || []
    
    if (calls.length === 0) {
      return {
        chainId,
        successRate: 0,
        averageLatency: 0,
        totalCalls: 0,
        failedCalls: 0,
        lastSuccess: null,
        lastFailure: null,
        status: 'unknown'
      }
    }

    const totalCalls = calls.length
    const successfulCalls = calls.filter(c => c.success)
    const failedCalls = calls.filter(c => !c.success)
    const successRate = successfulCalls.length / totalCalls
    
    const averageLatency = successfulCalls.length > 0 
      ? successfulCalls.reduce((sum, call) => sum + call.duration, 0) / successfulCalls.length
      : 0

    const lastSuccess = successfulCalls.length > 0 
      ? Math.max(...successfulCalls.map(c => c.timestamp))
      : null

    const lastFailure = failedCalls.length > 0
      ? Math.max(...failedCalls.map(c => c.timestamp))
      : null

    // Determine status based on success rate
    let status: ChainHealth['status']
    if (successRate >= 0.95) {
      status = 'healthy'
    } else if (successRate >= 0.80) {
      status = 'degraded'
    } else if (successRate > 0) {
      status = 'down'
    } else {
      status = 'down'
    }

    // Special case: if no successful calls in last 2 minutes, mark as down
    const twoMinutesAgo = Date.now() - 2 * 60 * 1000
    if (!lastSuccess || lastSuccess < twoMinutesAgo) {
      status = 'down'
    }

    return {
      chainId,
      successRate,
      averageLatency: Math.round(averageLatency),
      totalCalls,
      failedCalls: failedCalls.length,
      lastSuccess,
      lastFailure,
      status
    }
  }

  /**
   * Get overall RPC health summary
   */
  getHealthSummary(): RPCHealthSummary {
    const allChains = Array.from(this.callHistory.keys())
    const chainHealths = allChains.map(chainId => this.getChainHealth(chainId))

    const healthyChains = chainHealths.filter(c => c.status === 'healthy').length
    const degradedChains = chainHealths.filter(c => c.status === 'degraded').length
    const downChains = chainHealths.filter(c => c.status === 'down').length

    let overallStatus: RPCHealthSummary['overallStatus']
    if (downChains > 0) {
      overallStatus = 'down'
    } else if (degradedChains > 0) {
      overallStatus = 'degraded'
    } else if (healthyChains > 0) {
      overallStatus = 'healthy'
    } else {
      overallStatus = 'down'
    }

    return {
      overallStatus,
      totalChains: allChains.length,
      healthyChains,
      degradedChains,
      downChains,
      chains: chainHealths,
      lastUpdate: Date.now()
    }
  }

  /**
   * Record a successful RPC call
   */
  recordSuccess(chainId: number, duration: number): void {
    this.recordCall({
      chainId,
      success: true,
      duration,
      timestamp: Date.now()
    })
  }

  /**
   * Record a failed RPC call
   */
  recordFailure(chainId: number, duration: number, error: string): void {
    this.recordCall({
      chainId,
      success: false,
      duration,
      error,
      timestamp: Date.now()
    })
  }

  /**
   * Clear all history (useful for testing or reset)
   */
  clearHistory(): void {
    this.callHistory.clear()
  }

  /**
   * Get raw call history for debugging
   */
  getCallHistory(chainId?: number): RPCCallResult[] {
    if (chainId !== undefined) {
      return this.callHistory.get(chainId) || []
    }
    
    // Return all calls from all chains, sorted by timestamp
    const allCalls: RPCCallResult[] = []
    for (const calls of this.callHistory.values()) {
      allCalls.push(...calls)
    }
    return allCalls.sort((a, b) => b.timestamp - a.timestamp)
  }

  /**
   * Get chain names for display (maps chain IDs to readable names)
   */
  getChainName(chainId: number): string {
    const chainNames: Record<number, string> = {
      1: 'Ethereum',
      137: 'Polygon',
      42161: 'Arbitrum',
      10: 'Optimism',
      8453: 'Base',
      56: 'BSC',
      31337: 'Local (Anvil)'
    }
    return chainNames[chainId] || `Chain ${chainId}`
  }
}

// Export singleton instance
export const rpcHealthMonitor = new RPCHealthMonitor()

export default rpcHealthMonitor