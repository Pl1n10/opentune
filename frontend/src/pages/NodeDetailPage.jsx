import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { 
  ArrowLeft, 
  Server, 
  Clock, 
  FileCode,
  Trash2,
  Key,
  Copy,
  Check,
  AlertTriangle,
  RefreshCw,
  Download
} from 'lucide-react'
import { nodesApi, policiesApi } from '../api/client'
import { 
  Card, 
  CardHeader, 
  CardTitle, 
  CardContent, 
  Button, 
  StatusBadge, 
  LoadingSpinner,
  Select
} from '../components/ui'
import { Table, TableHead, TableBody, TableRow, TableHeader, TableCell } from '../components/Table'
import { Modal, ModalFooter } from '../components/Modal'

export default function NodeDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  
  const [node, setNode] = useState(null)
  const [runs, setRuns] = useState([])
  const [policies, setPolicies] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState(null)
  
  // Policy assignment
  const [selectedPolicyId, setSelectedPolicyId] = useState('')
  const [isAssigning, setIsAssigning] = useState(false)
  
  // Delete modal
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  
  // Regenerate token modal
  const [showRegenModal, setShowRegenModal] = useState(false)
  const [newToken, setNewToken] = useState(null)
  const [bootstrapUrl, setBootstrapUrl] = useState(null)
  const [isRegenerating, setIsRegenerating] = useState(false)
  const [tokenCopied, setTokenCopied] = useState(false)

  const loadData = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      const [nodeData, runsData, policiesData] = await Promise.all([
        nodesApi.get(id),
        nodesApi.getRuns(id, { limit: 10 }),
        policiesApi.list(),
      ])
      setNode(nodeData)
      setRuns(runsData)
      setPolicies(policiesData)
      setSelectedPolicyId(nodeData.assigned_policy_id?.toString() || '')
    } catch (err) {
      setError(err.message)
    } finally {
      setIsLoading(false)
    }
  }, [id])

  useEffect(() => {
    loadData()
  }, [loadData])

  const handleAssignPolicy = async () => {
    setIsAssigning(true)
    try {
      const policyId = selectedPolicyId ? parseInt(selectedPolicyId) : null
      const updated = await nodesApi.assignPolicy(id, policyId)
      setNode(updated)
    } catch (err) {
      console.error('Failed to assign policy:', err)
    } finally {
      setIsAssigning(false)
    }
  }

  const handleDelete = async () => {
    setIsDeleting(true)
    try {
      await nodesApi.delete(id)
      navigate('/nodes')
    } catch (err) {
      console.error('Failed to delete node:', err)
      setIsDeleting(false)
    }
  }

  const handleRegenerateToken = async () => {
    setIsRegenerating(true)
    try {
      // Use the new bootstrap endpoint that regenerates token and returns bootstrap URL
      const result = await nodesApi.getBootstrap(id)
      setNewToken(result.token)
      setBootstrapUrl(result.bootstrap_url)
    } catch (err) {
      console.error('Failed to regenerate token:', err)
    } finally {
      setIsRegenerating(false)
    }
  }

  const copyToken = async () => {
    if (newToken) {
      await navigator.clipboard.writeText(newToken)
      setTokenCopied(true)
      setTimeout(() => setTokenCopied(false), 2000)
    }
  }

  const formatDate = (date) => {
    if (!date) return 'Never'
    return new Date(date).toLocaleString()
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  if (error || !node) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600 mb-4">{error || 'Node not found'}</p>
        <Button variant="secondary" onClick={() => navigate('/nodes')}>
          Back to Nodes
        </Button>
      </div>
    )
  }

  const currentPolicy = policies.find(p => p.id === node.assigned_policy_id)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Button variant="ghost" onClick={() => navigate('/nodes')}>
          <ArrowLeft className="w-4 h-4" />
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-gray-100">
              <Server className="w-5 h-5 text-gray-600" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-gray-900">{node.name}</h1>
              <p className="text-sm text-gray-500">Node ID: {node.id}</p>
            </div>
          </div>
        </div>
        <StatusBadge status={node.last_status} />
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Node Info */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Node Information</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-gray-500">Status</p>
                <p className="font-medium mt-1">
                  <StatusBadge status={node.last_status} />
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Last Seen</p>
                <p className="font-medium text-gray-900 mt-1 flex items-center gap-1.5">
                  <Clock className="w-4 h-4 text-gray-400" />
                  {formatDate(node.last_seen_at)}
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Assigned Policy</p>
                <p className="font-medium text-gray-900 mt-1">
                  {currentPolicy ? (
                    <Link 
                      to={`/policies/${currentPolicy.id}`}
                      className="text-primary-600 hover:underline"
                    >
                      {currentPolicy.name}
                    </Link>
                  ) : (
                    <span className="text-gray-400 italic">None</span>
                  )}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Policy Assignment */}
        <Card>
          <CardHeader>
            <CardTitle>Assign Policy</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <Select
              label="Policy"
              value={selectedPolicyId}
              onChange={(e) => setSelectedPolicyId(e.target.value)}
            >
              <option value="">No policy (unassign)</option>
              {policies.map((policy) => (
                <option key={policy.id} value={policy.id}>
                  {policy.name}
                </option>
              ))}
            </Select>
            <Button 
              onClick={handleAssignPolicy} 
              isLoading={isAssigning}
              disabled={selectedPolicyId === (node.assigned_policy_id?.toString() || '')}
              className="w-full"
            >
              {selectedPolicyId ? 'Assign Policy' : 'Unassign Policy'}
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Recent Runs */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Recent Runs</CardTitle>
          <Button variant="ghost" size="sm" onClick={loadData}>
            <RefreshCw className="w-4 h-4" />
          </Button>
        </CardHeader>
        {runs.length === 0 ? (
          <CardContent>
            <p className="text-gray-500 text-center py-4">No runs recorded yet</p>
          </CardContent>
        ) : (
          <Table>
            <TableHead>
              <TableRow>
                <TableHeader>Status</TableHeader>
                <TableHeader>Policy</TableHeader>
                <TableHeader>Commit</TableHeader>
                <TableHeader>Started</TableHeader>
                <TableHeader>Summary</TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {runs.map((run) => (
                <TableRow key={run.id}>
                  <TableCell>
                    <StatusBadge status={run.status} />
                  </TableCell>
                  <TableCell className="text-gray-900">
                    {policies.find(p => p.id === run.policy_id)?.name || `Policy #${run.policy_id}`}
                  </TableCell>
                  <TableCell>
                    <code className="text-xs bg-gray-100 px-1.5 py-0.5 rounded">
                      {run.git_commit?.substring(0, 8) || 'N/A'}
                    </code>
                  </TableCell>
                  <TableCell className="text-gray-500 text-sm">
                    {formatDate(run.started_at)}
                  </TableCell>
                  <TableCell className="text-gray-600 text-sm max-w-xs truncate">
                    {run.summary || '-'}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      {/* Agent Management */}
      <Card>
        <CardHeader>
          <CardTitle>Agent Management</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between p-4 bg-blue-50 rounded-lg">
            <div>
              <p className="font-medium text-gray-900">Download Bootstrap Script</p>
              <p className="text-sm text-gray-500">
                Regenerate the token and download a bootstrap script to install/reinstall the agent.
              </p>
            </div>
            <Button variant="secondary" onClick={() => setShowRegenModal(true)}>
              <Download className="w-4 h-4" />
              Get Bootstrap
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Danger Zone */}
      <Card className="border-red-200">
        <CardHeader>
          <CardTitle className="text-red-600">Danger Zone</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between p-4 bg-red-50 rounded-lg">
            <div>
              <p className="font-medium text-gray-900">Delete Node</p>
              <p className="text-sm text-gray-500">
                Permanently delete this node and all its run history.
              </p>
            </div>
            <Button variant="danger" onClick={() => setShowDeleteModal(true)}>
              <Trash2 className="w-4 h-4" />
              Delete
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Delete Modal */}
      <Modal
        isOpen={showDeleteModal}
        onClose={() => setShowDeleteModal(false)}
        title="Delete Node"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-4 bg-red-50 rounded-lg">
            <AlertTriangle className="w-6 h-6 text-red-600 flex-shrink-0" />
            <div>
              <p className="font-medium text-red-900">This action cannot be undone</p>
              <p className="text-sm text-red-700">
                All run history for "{node.name}" will be permanently deleted.
              </p>
            </div>
          </div>
          <ModalFooter>
            <Button variant="secondary" onClick={() => setShowDeleteModal(false)}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleDelete} isLoading={isDeleting}>
              Delete Node
            </Button>
          </ModalFooter>
        </div>
      </Modal>

      {/* Regenerate Token Modal */}
      <Modal
        isOpen={showRegenModal}
        onClose={() => {
          setShowRegenModal(false)
          setNewToken(null)
          setBootstrapUrl(null)
          setTokenCopied(false)
        }}
        title={newToken ? 'Token Regenerated & Bootstrap Ready' : 'Regenerate Token & Get Bootstrap'}
      >
        {newToken ? (
          <div className="space-y-4">
            <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
              <div className="flex items-center gap-2 text-blue-700 font-medium mb-2">
                <Download className="w-5 h-5" />
                Bootstrap Script Ready
              </div>
              <p className="text-sm text-blue-600 mb-3">
                Download and run this script on your Windows machine to install/reinstall the agent.
              </p>
              {bootstrapUrl && (
                <a
                  href={bootstrapUrl}
                  download={`bootstrap-${node?.name || 'node'}.ps1`}
                  className="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm font-medium"
                >
                  <Download className="w-4 h-4" />
                  Download Bootstrap Script
                </a>
              )}
            </div>
            
            <div className="p-4 bg-amber-50 border border-amber-200 rounded-lg">
              <div className="flex items-center gap-2 text-amber-700 font-medium mb-2">
                <AlertTriangle className="w-5 h-5" />
                New Token (for manual setup)
              </div>
              <p className="text-sm text-amber-600 mb-3">
                The old token has been invalidated. Save this new token if you prefer manual configuration.
              </p>
              <div className="flex items-center gap-2">
                <code className="flex-1 p-2 bg-white border border-amber-300 rounded text-xs font-mono break-all">
                  {newToken}
                </code>
                <Button variant="secondary" size="sm" onClick={copyToken}>
                  {tokenCopied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                </Button>
              </div>
            </div>
            <ModalFooter>
              <Button onClick={() => {
                setShowRegenModal(false)
                setNewToken(null)
                setBootstrapUrl(null)
              }}>
                Done
              </Button>
            </ModalFooter>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center gap-3 p-4 bg-amber-50 rounded-lg">
              <AlertTriangle className="w-6 h-6 text-amber-600 flex-shrink-0" />
              <div>
                <p className="font-medium text-amber-900">The current token will be invalidated</p>
                <p className="text-sm text-amber-700">
                  A new bootstrap script will be generated with the new token.
                </p>
              </div>
            </div>
            <ModalFooter>
              <Button variant="secondary" onClick={() => setShowRegenModal(false)}>
                Cancel
              </Button>
              <Button onClick={handleRegenerateToken} isLoading={isRegenerating}>
                <Download className="w-4 h-4" />
                Regenerate & Get Bootstrap
              </Button>
            </ModalFooter>
          </div>
        )}
      </Modal>
    </div>
  )
}
