import { useEffect, useState, useCallback } from 'react'
import { Link } from 'react-router-dom'
import {
  Server,
  CheckCircle2,
  XCircle,
  HelpCircle,
  Activity,
  GitBranch,
  FileCode,
  ArrowRight,
  RefreshCw
} from 'lucide-react'
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { nodesApi, policiesApi, repositoriesApi, runsApi } from '../api/client'
import { Card, CardHeader, CardTitle, CardContent, StatCard, LoadingSpinner, StatusBadge, Button } from '../components/ui'
import { Table, TableHead, TableBody, TableRow, TableHeader, TableCell } from '../components/Table'

export default function DashboardPage() {
  const [stats, setStats] = useState(null)
  const [nodes, setNodes] = useState([])
  const [recentRuns, setRecentRuns] = useState([])
  const [counts, setCounts] = useState({ repos: 0, policies: 0 })
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState(null)

  // Normalizza qualsiasi risposta "lista" in un array
  const normalizeList = (data) => {
    if (Array.isArray(data)) return data
    if (Array.isArray(data?.items)) return data.items
    return []
  }

  const loadData = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      const [statsData, nodesData, runsData] = await Promise.all([
        runsApi.getStats(24),
        nodesApi.list({ limit: 100 }),
        runsApi.list({ limit: 5 }),
      ])

      setStats(statsData)
      setNodes(normalizeList(nodesData))
      setRecentRuns(normalizeList(runsData))

      // Per i count prendiamo la lunghezza delle liste complete
      const allRepos = normalizeList(await repositoriesApi.list())
      const allPolicies = normalizeList(await policiesApi.list())
      setCounts({
        repos: allRepos.length,
        policies: allPolicies.length,
      })
    } catch (err) {
      setError(err.message)
      console.error('Dashboard load error:', err)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600 mb-4">{error}</p>
        <Button onClick={loadData}>Retry</Button>
      </div>
    )
  }

  // Calculate node status breakdown
  const statusCounts = (nodes || []).reduce((acc, node) => {
    const status = node.last_status || 'unknown'
    acc[status] = (acc[status] || 0) + 1
    return acc
  }, {})

  const successCount = statusCounts.success || 0
  const failedCount = statusCounts.failed || 0
  const unknownCount = nodes.length - successCount - failedCount

  // Pie chart data
  const pieData = [
    { name: 'Success', value: successCount, color: '#22c55e' },
    { name: 'Failed', value: failedCount, color: '#ef4444' },
    { name: 'Other', value: unknownCount, color: '#9ca3af' },
  ].filter(d => d.value > 0)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
          <p className="text-gray-500 mt-1">Overview of your OpenTune deployment</p>
        </div>
        <Button variant="secondary" onClick={loadData}>
          <RefreshCw className="w-4 h-4" />
          Refresh
        </Button>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Total Nodes"
          value={nodes.length}
          icon={Server}
        />
        <StatCard
          title="Success"
          value={successCount}
          icon={CheckCircle2}
        />
        <StatCard
          title="Failed"
          value={failedCount}
          icon={XCircle}
        />
        <StatCard
          title="Success Rate (24h)"
          value={`${stats?.success_rate_percent || 0}%`}
          icon={Activity}
        />
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Status Chart */}
        <Card>
          <CardHeader>
            <CardTitle>Node Status Distribution</CardTitle>
          </CardHeader>
          <CardContent>
            {pieData.length > 0 ? (
              <div className="h-48">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={pieData}
                      cx="50%"
                      cy="50%"
                      innerRadius={50}
                      outerRadius={70}
                      paddingAngle={2}
                      dataKey="value"
                    >
                      {pieData.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <Tooltip
                      formatter={(value, name) => [`${value} nodes`, name]}
                    />
                  </PieChart>
                </ResponsiveContainer>
                <div className="flex justify-center gap-4 mt-2">
                  {pieData.map((entry) => (
                    <div key={entry.name} className="flex items-center gap-1.5 text-sm">
                      <div
                        className="w-3 h-3 rounded-full"
                        style={{ backgroundColor: entry.color }}
                      />
                      <span className="text-gray-600">{entry.name}: {entry.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="h-48 flex items-center justify-center text-gray-500">
                No data available
              </div>
            )}
          </CardContent>
        </Card>

        {/* Quick Stats */}
        <Card>
          <CardHeader>
            <CardTitle>Resources</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <Link
              to="/repositories"
              className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-purple-100">
                  <GitBranch className="w-5 h-5 text-purple-600" />
                </div>
                <div>
                  <p className="font-medium text-gray-900">Repositories</p>
                  <p className="text-sm text-gray-500">{counts.repos} registered</p>
                </div>
              </div>
              <ArrowRight className="w-5 h-5 text-gray-400" />
            </Link>

            <Link
              to="/policies"
              className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-blue-100">
                  <FileCode className="w-5 h-5 text-blue-600" />
                </div>
                <div>
                  <p className="font-medium text-gray-900">Policies</p>
                  <p className="text-sm text-gray-500">{counts.policies} defined</p>
                </div>
              </div>
              <ArrowRight className="w-5 h-5 text-gray-400" />
            </Link>

            <Link
              to="/nodes"
              className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-green-100">
                  <Server className="w-5 h-5 text-green-600" />
                </div>
                <div>
                  <p className="font-medium text-gray-900">Nodes</p>
                  <p className="text-sm text-gray-500">{nodes.length} registered</p>
                </div>
              </div>
              <ArrowRight className="w-5 h-5 text-gray-400" />
            </Link>
          </CardContent>
        </Card>

        {/* 24h Stats */}
        <Card>
          <CardHeader>
            <CardTitle>Last 24 Hours</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between py-2 border-b border-gray-100">
              <span className="text-gray-600">Total Runs</span>
              <span className="font-semibold text-gray-900">{stats?.total_runs || 0}</span>
            </div>
            <div className="flex items-center justify-between py-2 border-b border-gray-100">
              <span className="text-gray-600">Successful</span>
              <span className="font-semibold text-green-600">{stats?.by_status?.success || 0}</span>
            </div>
            <div className="flex items-center justify-between py-2 border-b border-gray-100">
              <span className="text-gray-600">Failed</span>
              <span className="font-semibold text-red-600">{stats?.by_status?.failed || 0}</span>
            </div>
            <div className="flex items-center justify-between py-2">
              <span className="text-gray-600">Nodes Reporting</span>
              <span className="font-semibold text-gray-900">{stats?.unique_nodes_reporting || 0}</span>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Recent Runs */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Recent Runs</CardTitle>
          <Link
            to="/runs"
            className="text-sm text-primary-600 hover:text-primary-700 font-medium"
          >
            View all
          </Link>
        </CardHeader>
        <Table>
          <TableHead>
            <TableRow>
              <TableHeader>Node</TableHeader>
              <TableHeader>Policy</TableHeader>
              <TableHeader>Status</TableHeader>
              <TableHeader>Time</TableHeader>
            </TableRow>
          </TableHead>
          <TableBody>
            {recentRuns.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} className="text-center text-gray-500 py-8">
                  No runs recorded yet
                </TableCell>
              </TableRow>
            ) : (
              recentRuns.map((run) => (
                <TableRow key={run.id}>
                  <TableCell className="font-medium text-gray-900">
                    {run.node_name || `Node #${run.node_id}`}
                  </TableCell>
                  <TableCell className="text-gray-600">
                    {run.policy_name || `Policy #${run.policy_id}`}
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={run.status} />
                  </TableCell>
                  <TableCell className="text-gray-500">
                    {new Date(run.started_at).toLocaleString()}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </Card>
    </div>
  )
}
