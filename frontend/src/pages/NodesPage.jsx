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
  AlertTriangle
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

export default function NodesPage() {
  const [nodes, setNodes] = useState([])
  const [policies, setPolicies] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [newNodeName, setNewNodeName] = useState('')
  const [createdNode, setCreatedNode] = useState(null)
  const [isCreating, setIsCreating] = useState(false)
  const [createError, setCreateError] = useState('')
  const [tokenCopied, setTokenCopied] = useState(false)
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

  const handleCreateNode = async () => {
    if (!newNodeName.trim()) {
      setCreateError('Please enter a node name')
      return
    }

    setIsCreating(true)
    setCreateError('')

    try {
      const result = await nodesApi.create({ name: newNodeName.trim() })
      setCreatedNode(result)
      setNodes(prev => [...prev, result.node])
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
    setCreateError('')
    setTokenCopied(false)
  }

  const copyToken = async () => {
    if (createdNode?.token) {
      await navigator.clipboard.writeText(createdNode.token)
      setTokenCopied(true)
      setTimeout(() => setTokenCopied(false), 2000)
    }
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
        title={createdNode ? 'Node Created Successfully' : 'Create New Node'}
      >
        {createdNode ? (
          <div className="space-y-4">
            <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
              <div className="flex items-center gap-2 text-green-700 font-medium mb-2">
                <Check className="w-5 h-5" />
                Node "{createdNode.node.name}" created
              </div>
              <p className="text-sm text-green-600">
                ID: {createdNode.node.id}
              </p>
            </div>

            <div className="p-4 bg-amber-50 border border-amber-200 rounded-lg">
              <div className="flex items-center gap-2 text-amber-700 font-medium mb-2">
                <AlertTriangle className="w-5 h-5" />
                Save this token now!
              </div>
              <p className="text-sm text-amber-600 mb-3">
                This token will only be shown once. Store it securely.
              </p>
              <div className="flex items-center gap-2">
                <code className="flex-1 p-2 bg-white border border-amber-300 rounded text-xs font-mono break-all">
                  {createdNode.token}
                </code>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={copyToken}
                >
                  {tokenCopied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                </Button>
              </div>
            </div>

            <ModalFooter>
              <Button onClick={handleCloseCreateModal}>Done</Button>
            </ModalFooter>
          </div>
        ) : (
          <div className="space-y-4">
            <Input
              label="Node Name"
              placeholder="e.g., pc-genitori, server-web-01"
              value={newNodeName}
              onChange={(e) => setNewNodeName(e.target.value)}
              error={createError}
              autoFocus
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
