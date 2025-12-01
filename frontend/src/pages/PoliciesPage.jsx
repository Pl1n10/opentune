import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { 
  FileCode, 
  Plus, 
  Search, 
  Pencil,
  Trash2,
  RefreshCw,
  GitBranch,
  Server,
  AlertTriangle
} from 'lucide-react'
import { policiesApi, repositoriesApi, nodesApi } from '../api/client'
import { 
  Card, 
  PageHeader, 
  Button, 
  LoadingSpinner,
  EmptyState,
  Input,
  Select
} from '../components/ui'
import { Table, TableHead, TableBody, TableRow, TableHeader, TableCell } from '../components/Table'
import { Modal, ModalFooter } from '../components/Modal'

export default function PoliciesPage() {
  const [policies, setPolicies] = useState([])
  const [repositories, setRepositories] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const navigate = useNavigate()
  
  // Modal state
  const [showModal, setShowModal] = useState(false)
  const [editingPolicy, setEditingPolicy] = useState(null)
  const [formData, setFormData] = useState({
    name: '',
    git_repository_id: '',
    branch: '',
    config_path: '',
  })
  const [formError, setFormError] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  
  // Delete modal
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [deletingPolicy, setDeletingPolicy] = useState(null)
  const [isDeleting, setIsDeleting] = useState(false)

  const loadData = useCallback(async () => {
    setIsLoading(true)
    try {
      const [policiesData, reposData] = await Promise.all([
        policiesApi.list(),
        repositoriesApi.list(),
      ])
      setPolicies(policiesData)
      setRepositories(reposData)
    } catch (err) {
      console.error('Failed to load policies:', err)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
  }, [loadData])

  const openCreateModal = () => {
    setEditingPolicy(null)
    setFormData({
      name: '',
      git_repository_id: repositories[0]?.id?.toString() || '',
      branch: '',
      config_path: '',
    })
    setFormError('')
    setShowModal(true)
  }

  const openEditModal = (policy) => {
    setEditingPolicy(policy)
    setFormData({
      name: policy.name,
      git_repository_id: policy.git_repository_id?.toString() || '',
      branch: policy.branch || '',
      config_path: policy.config_path,
    })
    setFormError('')
    setShowModal(true)
  }

  const handleSave = async () => {
    // Validation
    if (!formData.name.trim()) {
      setFormError('Name is required')
      return
    }
    if (!formData.git_repository_id) {
      setFormError('Repository is required')
      return
    }
    if (!formData.config_path.trim()) {
      setFormError('Config path is required')
      return
    }

    setIsSaving(true)
    setFormError('')

    try {
      const payload = {
        name: formData.name.trim(),
        git_repository_id: parseInt(formData.git_repository_id),
        branch: formData.branch.trim() || null,
        config_path: formData.config_path.trim(),
      }

      if (editingPolicy) {
        const updated = await policiesApi.update(editingPolicy.id, payload)
        setPolicies(prev => prev.map(p => p.id === editingPolicy.id ? updated : p))
      } else {
        const created = await policiesApi.create(payload)
        setPolicies(prev => [...prev, created])
      }
      
      setShowModal(false)
    } catch (err) {
      setFormError(err.message || 'Failed to save policy')
    } finally {
      setIsSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!deletingPolicy) return
    
    setIsDeleting(true)
    try {
      await policiesApi.delete(deletingPolicy.id)
      setPolicies(prev => prev.filter(p => p.id !== deletingPolicy.id))
      setShowDeleteModal(false)
      setDeletingPolicy(null)
    } catch (err) {
      console.error('Failed to delete policy:', err)
    } finally {
      setIsDeleting(false)
    }
  }

  const filteredPolicies = policies.filter(policy =>
    policy.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    policy.config_path.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const getRepoName = (repoId) => {
    const repo = repositories.find(r => r.id === repoId)
    return repo?.name || `Repo #${repoId}`
  }

  return (
    <div className="space-y-6">
      <PageHeader 
        title="Policies"
        description="Define DSC configuration policies"
        action={
          <Button onClick={openCreateModal} disabled={repositories.length === 0}>
            <Plus className="w-4 h-4" />
            Add Policy
          </Button>
        }
      />

      {repositories.length === 0 && !isLoading && (
        <div className="p-4 bg-amber-50 border border-amber-200 rounded-lg flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 text-amber-600" />
          <p className="text-amber-800">
            You need to <button onClick={() => navigate('/repositories')} className="underline font-medium">add a repository</button> before creating policies.
          </p>
        </div>
      )}

      {/* Search */}
      <div className="flex items-center gap-4">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search policies..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>
        <Button variant="secondary" onClick={loadData}>
          <RefreshCw className="w-4 h-4" />
        </Button>
      </div>

      {/* Policies Table */}
      <Card>
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : filteredPolicies.length === 0 ? (
          <EmptyState
            icon={FileCode}
            title={searchQuery ? 'No policies found' : 'No policies yet'}
            description={searchQuery ? 'Try a different search term' : 'Create your first policy to get started'}
            action={!searchQuery && repositories.length > 0 && (
              <Button onClick={openCreateModal}>
                <Plus className="w-4 h-4" />
                Add Policy
              </Button>
            )}
          />
        ) : (
          <Table>
            <TableHead>
              <TableRow>
                <TableHeader>Name</TableHeader>
                <TableHeader>Repository</TableHeader>
                <TableHeader>Branch</TableHeader>
                <TableHeader>Config Path</TableHeader>
                <TableHeader></TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {filteredPolicies.map((policy) => (
                <TableRow key={policy.id}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded-lg bg-blue-100">
                        <FileCode className="w-4 h-4 text-blue-600" />
                      </div>
                      <span className="font-medium text-gray-900">{policy.name}</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1.5 text-gray-600">
                      <GitBranch className="w-4 h-4 text-gray-400" />
                      {policy.repository_name || getRepoName(policy.git_repository_id)}
                    </div>
                  </TableCell>
                  <TableCell>
                    <code className="text-xs bg-gray-100 px-1.5 py-0.5 rounded">
                      {policy.branch || 'default'}
                    </code>
                  </TableCell>
                  <TableCell>
                    <code className="text-xs text-gray-600">{policy.config_path}</code>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <Button 
                        variant="ghost" 
                        size="sm"
                        onClick={() => openEditModal(policy)}
                      >
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button 
                        variant="ghost" 
                        size="sm"
                        onClick={() => {
                          setDeletingPolicy(policy)
                          setShowDeleteModal(true)
                        }}
                      >
                        <Trash2 className="w-4 h-4 text-red-500" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      {/* Create/Edit Modal */}
      <Modal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        title={editingPolicy ? 'Edit Policy' : 'Create Policy'}
      >
        <div className="space-y-4">
          <Input
            label="Policy Name"
            placeholder="e.g., security-baseline, workstation-config"
            value={formData.name}
            onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
          />
          
          <Select
            label="Git Repository"
            value={formData.git_repository_id}
            onChange={(e) => setFormData(prev => ({ ...prev, git_repository_id: e.target.value }))}
          >
            <option value="">Select a repository</option>
            {repositories.map((repo) => (
              <option key={repo.id} value={repo.id}>
                {repo.name}
              </option>
            ))}
          </Select>
          
          <Input
            label="Branch (optional)"
            placeholder="Leave empty for default branch"
            value={formData.branch}
            onChange={(e) => setFormData(prev => ({ ...prev, branch: e.target.value }))}
          />
          
          <Input
            label="Config Path"
            placeholder="e.g., nodes/pc-genitori.ps1 or mof/server-baseline"
            value={formData.config_path}
            onChange={(e) => setFormData(prev => ({ ...prev, config_path: e.target.value }))}
          />
          
          <p className="text-sm text-gray-500">
            Path to the DSC configuration file (.ps1) or MOF directory relative to the repository root.
          </p>

          {formError && (
            <p className="text-sm text-red-600">{formError}</p>
          )}

          <ModalFooter>
            <Button variant="secondary" onClick={() => setShowModal(false)}>
              Cancel
            </Button>
            <Button onClick={handleSave} isLoading={isSaving}>
              {editingPolicy ? 'Save Changes' : 'Create Policy'}
            </Button>
          </ModalFooter>
        </div>
      </Modal>

      {/* Delete Modal */}
      <Modal
        isOpen={showDeleteModal}
        onClose={() => setShowDeleteModal(false)}
        title="Delete Policy"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-4 bg-red-50 rounded-lg">
            <AlertTriangle className="w-6 h-6 text-red-600 flex-shrink-0" />
            <div>
              <p className="font-medium text-red-900">Delete "{deletingPolicy?.name}"?</p>
              <p className="text-sm text-red-700">
                Any nodes assigned to this policy will be unassigned.
              </p>
            </div>
          </div>
          <ModalFooter>
            <Button variant="secondary" onClick={() => setShowDeleteModal(false)}>
              Cancel
            </Button>
            <Button variant="danger" onClick={handleDelete} isLoading={isDeleting}>
              Delete Policy
            </Button>
          </ModalFooter>
        </div>
      </Modal>
    </div>
  )
}
