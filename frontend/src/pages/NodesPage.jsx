import { useState, useEffect, useCallback } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { 
  Server, 
  Plus, 
  Search, 
  MoreVertical,
  Trash2,
  Eye,
  RefreshCw,
  Clock,
  Copy,
  Check,
  AlertTriangle,
  Download,
  Terminal
} from 'lucide-react'
import { nodesApi, policiesApi } from '../api/client'
import { 
  Card, 
  CardContent, 
  PageHeader, 
  Button, 
  StatusBadge, 
  LoadingSpinner,
  EmptyState,
  Input
} from '../components/ui'
import { Table, TableHead, TableBody, TableRow, TableHeader, TableCell } from '../components/Table'
import { Modal, ModalFooter } from '../components/Modal'
import { CopyButton, CodeBlockWithCopy } from '../components/CopyButton'
import { 
  getServerBaseUrl, 
  getBootstrapUrl, 
  generatePowerShellBootstrapCommand,
  copyToClipboard 
} from '../utils/url'

export default function NodesPage() {
  const [nodes, setNodes] = useState([])
  const [policies, setPolicies] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [newNodeName, setNewNodeName] = useState('')
  const [createdNode, setCreatedNode] = useState(null)
  const [bootstrapData, setBootstrapData] = useState(null) // { token, bootstrap_url, powershell_command }
  const [isCreating, setIsCreating] = useState(false)
  const [createError, setCreateError] = useState('')
  const navigate = useNavigate()

  const loadData = useCallback(async () => {
    setIsLoading(true)
    try {
      const [nodesData, policiesData] = await Promise.all([
        nodesApi.list(),
        policiesApi.list(),
      ])
      setNodes(nodesData)
      setPolicies(policiesData)
    } catch (err) {
      console.error('Failed to load nodes:', err)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  /**
   * Create a new node and fetch bootstrap info.
   * Flow:
   * 1. POST /nodes/ to create the node (returns node + token)
   * 2. Use the token to build the PowerShell bootstrap command
   */
  const handleCreateNode = async () => {
    if (!newNodeName.trim()) {
      setCreateError('Please enter a node name')
      return
    }

    setIsCreating(true)
    setCreateError('')

    try {
      // Step 1: Create the node
      const result = await nodesApi.create({ name: newNodeName.trim() })
      setCreatedNode(result)
      setNodes(prev => [...prev, result.node])
      
      // Step 2: Build bootstrap data using the returned token
      // We use our frontend utility to build the URL and PowerShell command
      // This ensures the URL uses the correct server address (from env or auto-detect)
      const nodeId = result.node.id
      const nodeName = result.node.name
      const token = result.token
      
      const bootstrapUrl = getBootstrapUrl(nodeId, token)
      const powershellCommand = generatePowerShellBootstrapCommand(nodeId, nodeName, token)
      
      setBootstrapData({
        token,
        bootstrap_url: bootstrapUrl,
        powershell_command: powershellCommand,
      })
      
    } catch (err) {
      setCreateError(err.message || 'Failed to create node')
    } finally {
      setIsCreating(false)
    }
  }

  const handleCloseCreateModal = () => {
    setShowCreateModal(false)
    setNewNodeName('')
    setCreatedNode(null)
    setBootstrapData(null)
    setCreateError('')
  }

  // Filter nodes by search
  const filteredNodes = nodes.filter(node => 
    node.name.toLowerCase().includes(searchQuery.toLowerCase())
  )

  // Get policy name for a node
  const getPolicyName = (policyId) => {
    if (!policyId) return null
    const policy = policies.find(p => p.id === policyId)
    return policy?.name || `Policy #${policyId}`
  }

  // Format relative time
  const formatLastSeen = (date) => {
    if (!date) return 'Never'
    const now = new Date()
    const seen = new Date(date)
    const diffMs = now - seen
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMins / 60)
    const diffDays = Math.floor(diffHours / 24)

    if (diffMins < 1) return 'Just now'
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    return `${diffDays}d ago`
  }

  return (
    <div className="space-y-6">
      <PageHeader 
        title="Nodes"
        description="Manage your Windows nodes"
        action={
          <Button onClick={() => setShowCreateModal(true)}>
            <Plus className="w-4 h-4" />
            Add Node
          </Button>
        }
      />

      {/* Search and filters */}
      <div className="flex items-center gap-4">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search nodes..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>
        <Button variant="secondary" onClick={loadData}>
          <RefreshCw className="w-4 h-4" />
        </Button>
      </div>

      {/* Nodes Table */}
      <Card>
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : filteredNodes.length === 0 ? (
          <EmptyState
            icon={Server}
            title={searchQuery ? 'No nodes found' : 'No nodes yet'}
            description={searchQuery ? 'Try a different search term' : 'Create your first node to get started'}
            action={!searchQuery && (
              <Button onClick={() => setShowCreateModal(true)}>
                <Plus className="w-4 h-4" />
                Add Node
              </Button>
            )}
          />
        ) : (
          <Table>
            <TableHead>
              <TableRow>
                <TableHeader>Name</TableHeader>
                <TableHeader>Status</TableHeader>
                <TableHeader>Policy</TableHeader>
                <TableHeader>Last Seen</TableHeader>
                <TableHeader></TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredNodes.map((node) => (
                <TableRow 
                  key={node.id}
                  onClick={() => navigate(`/nodes/${node.id}`)}
                  className="cursor-pointer"
                >
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-gray-100">
                        <Server className="w-4 h-4 text-gray-600" />
                      </div>
                      <span className="font-medium text-gray-900">{node.name}</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={node.last_status} />
                  </TableCell>
                  <TableCell>
                    {node.assigned_policy_id ? (
                      <span className="text-gray-900">{getPolicyName(node.assigned_policy_id)}</span>
                    ) : (
                      <span className="text-gray-400 italic">Not assigned</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1.5 text-gray-500">
                      <Clock className="w-4 h-4" />
                      {formatLastSeen(node.last_seen_at)}
                    </div>
                  </TableCell>
                  <TableCell>
                    <Button 
                      variant="ghost" 
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation()
                        navigate(`/nodes/${node.id}`)
                      }}
                    >
                      <Eye className="w-4 h-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      {/* Create Node Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={handleCloseCreateModal}
        title={createdNode ? 'Node Created – Bootstrap Instructions' : 'Create New Node'}
        size={createdNode ? 'lg' : 'md'}
      >
        {createdNode && bootstrapData ? (
          // ========================================
          // SUCCESS STATE: Show bootstrap instructions
          // ========================================
          <div className="space-y-5">
            {/* Success banner */}
            <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
              <div className="flex items-center gap-2 text-green-700 font-medium">
                <Check className="w-5 h-5" />
                Node "{createdNode.node.name}" created successfully
              </div>
              <p className="text-sm text-green-600 mt-1">
                Node ID: {createdNode.node.id}
              </p>
            </div>

            {/* Main section: PowerShell command */}
            <div className="space-y-3">
              <div className="flex items-center gap-2 text-gray-900 font-medium">
                <Terminal className="w-5 h-5 text-blue-600" />
                Run this on your Windows machine
              </div>
              <p className="text-sm text-gray-600">
                Open PowerShell <strong>as Administrator</strong> and paste this command:
              </p>
              
              {/* PowerShell code block with copy button */}
              <CodeBlockWithCopy 
                code={bootstrapData.powershell_command}
                language="powershell"
                label="Copy"
              />
            </div>

            {/* Alternative: Direct download */}
            <div className="p-4 bg-gray-50 border border-gray-200 rounded-lg">
              <div className="flex items-center gap-2 text-gray-700 font-medium mb-2">
                <Download className="w-5 h-5" />
                Alternative: Direct Download
              </div>
              <p className="text-sm text-gray-600 mb-3">
                Or download the bootstrap script directly:
              </p>
              <a
                href={bootstrapData.bootstrap_url}
                download={`bootstrap-${createdNode.node.name}.ps1`}
                className="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm font-medium"
              >
                <Download className="w-4 h-4" />
                Download bootstrap-{createdNode.node.name}.ps1
              </a>
            </div>

            {/* Collapsed section: Raw token (for advanced users) */}
            <details className="group">
              <summary className="cursor-pointer text-sm text-gray-500 hover:text-gray-700 flex items-center gap-2">
                <AlertTriangle className="w-4 h-4" />
                Show raw token (for manual setup)
              </summary>
              <div className="mt-3 p-4 bg-amber-50 border border-amber-200 rounded-lg">
                <p className="text-sm text-amber-700 mb-2">
                  <strong>Warning:</strong> This token is shown only once. Save it if you need manual installation.
                </p>
                <div className="flex items-center gap-2">
                  <code className="flex-1 p-2 bg-white border border-amber-300 rounded text-xs font-mono break-all select-all">
                    {bootstrapData.token}
                  </code>
                  <CopyButton text={bootstrapData.token} />
                </div>
              </div>
            </details>

            <ModalFooter>
              <Button onClick={handleCloseCreateModal}>Done</Button>
            </ModalFooter>
          </div>
        ) : (
          // ========================================
          // INPUT STATE: Node name form
          // ========================================
          <div className="space-y-4">
            <Input
              label="Node Name"
              placeholder="e.g., pc-genitori, server-web-01"
              value={newNodeName}
              onChange={(e) => setNewNodeName(e.target.value)}
              error={createError}
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !isCreating) {
                  handleCreateNode()
                }
              }}
            />
            <p className="text-sm text-gray-500">
              Use a descriptive name like the hostname or a unique identifier.
            </p>

            <ModalFooter>
              <Button variant="secondary" onClick={handleCloseCreateModal}>
                Cancel
              </Button>
              <Button onClick={handleCreateNode} isLoading={isCreating}>
                Create Node
              </Button>
            </ModalFooter>
          </div>
        )}
      </Modal>
    </div>
  )
}
