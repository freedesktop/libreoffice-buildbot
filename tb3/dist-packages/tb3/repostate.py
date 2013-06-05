#! /usr/bin/env python
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import sh
import json
import datetime

class StateEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime.datetime):
            return [ '__datetime__', (obj - datetime.datetime(1970,1,1)).total_seconds() ]
        elif isinstance(obj, datetime.timedelta):
            return [ '__timedelta__', obj.total_seconds() ]
        return json.JSONEncoder.default(self, obj)

class StateDecoder(json.JSONDecoder):
    def decode(self, s):
        obj = super(StateDecoder, self).decode(s)
        for (key, value) in obj.iteritems():
            if isinstance(value, list):
                if value[0] == '__datetime__':
                    obj[key] = datetime.datetime.utcfromtimestamp(value[1])
                elif value[0] == '__timedelta__':
                    obj[key] = datetime.timedelta(float(value[1]))
        return obj

class RepoState:
    def __init__(self, platform, branch, repo):
        self.platform = platform
        self.branch = branch
        self.repo = repo
        self.git = sh.git.bake(_cwd=repo)
    def __str__(self):
        (last_good, first_bad, last_bad) = (self.get_last_good(), self.get_first_bad(), self.get_last_bad())
        result = 'State of repository %s on branch %s for platform %s' % (self.repo, self.branch, self.platform)
        result += '\nhead            : %s' % (self.get_head())
        if last_good:
            result += '\nlast good commit: %s (%s-%d)' % (last_good, self.branch, self.__distance_to_branch_head(last_good))
        if first_bad:
            result += '\nfirst bad commit: %s (%s-%d)' % (first_bad, self.branch, self.__distance_to_branch_head(first_bad))
        if last_bad:
            result += '\nlast  bad commit: %s (%s-%d)' % (last_bad, self.branch, self.__distance_to_branch_head(last_bad))
        return result
    def __resolve_ref(self, refname):
        try:
            return self.git('show-ref', refname).split(' ')[0]
        except sh.ErrorReturnCode_1:
            return None
    def __distance_to_branch_head(self, commit):
        return int(self.git('rev-list', '--count', '%s..%s' % (commit, self.branch)))
    def __get_fullref(self, name):
        return 'refs/tb3/state/%s/%s/%s' % (self.platform, self.branch, name)
    def __set_ref(self, refname, target):
        return self.git('update-ref', refname, target)
    def __clear_ref(self, refname):
        return self.git('update-ref', '-d', self.__get_fullref(refname))
    def sync(self):
        self.git('fetch', all=True)
    def get_last_good(self):
        return self.__resolve_ref(self.__get_fullref('last_good'))
    def set_last_good(self, target):
        self.__set_ref(self.__get_fullref('last_good'),target)
    def clear_last_good(self):
        self.__clear_ref('last_good')
    def get_first_bad(self):
        return self.__resolve_ref(self.__get_fullref('first_bad'))
    def set_first_bad(self, target):
        self.__set_ref(self.__get_fullref('first_bad'), target)
    def clear_first_bad(self):
        self.__clear_ref('first_bad')
    def get_last_bad(self):
        return self.__resolve_ref(self.__get_fullref('last_bad'))
    def set_last_bad(self, target):
        self.__set_ref(self.__get_fullref('last_bad'), target)
    def clear_last_bad(self):
        self.__clear_ref('last_bad')
    def get_head(self):
        return self.__resolve_ref('refs/heads/%s' % self.branch)
    def get_last_build(self):
        (last_bad, last_good) = (self.get_last_bad(), self.get_last_good())
        if not last_bad:
            return last_good
        if not last_good:
            return last_bad
        if self.git('merge-base', '--is-ancestor', last_good, last_bad, _ok_code=[0,1]).exit_code == 0:
            return last_bad
        return last_good

class CommitState:
    STATES=['BAD', 'GOOD', 'ASSUMED_GOOD', 'ASSUMED_BAD', 'POSSIBLY_BREAKING', 'POSSIBLY_FIXING', 'UNKNOWN', 'RUNNING', 'BREAKING']
    def __init__(self, state='UNKNOWN', started=None, builder=None, estimated_duration=None, finished=None, artifactreference=None):
        if not state in CommitState.STATES:
            raise AttributeError
        self.state = state
        self.builder = builder
        self.started = started
        self.finished = finished
        self.estimated_duration = estimated_duration
        self.artifactreference = artifactreference
    def __eq__(self, other):
        if not hasattr(other, '__dict__'):
            return False
        return self.__dict__ == other.__dict__
    def __str__(self):
        result = 'started on %s with builder %s and finished on %s -- artifacts at %s, state: %s' % (self.started, self.builder, self.finished, self.artifactreference, self.state)
        if self.started and self.finished:
            result += ' (took %s)' % (self.finished-self.started)
        if self.estimated_duration:
            result += ' (estimated %s)' % (self.estimated_duration)
        return result

class RepoHistory:
    def __init__(self, platform, repo):
        self.platform = platform
        self.git = sh.git.bake(_cwd=repo)
        self.gitnotes = sh.git.bake('--no-pager', 'notes', '--ref', 'core.notesRef=refs/notes/tb3/history/%s' % self.platform, _cwd=repo)
    def get_commit_state(self, commit):
        commitstate_json = str(self.gitnotes.show(commit, _ok_code=[0,1]))
        commitstate = CommitState()
        if len(commitstate_json):
            commitstate.__dict__ = json.loads(commitstate_json, cls=StateDecoder)
        return commitstate
    def get_recent_commit_states(self, branch, count):
        commits = self.git('rev-list', '%s~%d..%s' % (branch, count, branch)).split('\n')[:-1]
        return [(c, self.get_commit_state(c)) for c in commits]
    def set_commit_state(self, commit, commitstate):
        self.gitnotes.add(commit, force=True, m=json.dumps(commitstate.__dict__, cls=StateEncoder)) 
    def update_inner_range_state(self, begin, end, commitstate, skipstates):
        for commit in self.git('rev-list', '%s..%s' % (begin, end)).split('\n')[1:-1]:
            oldstate = self.get_commit_state(commit)
            if not oldstate.state in skipstates:
                self.set_commit_state(commit, commitstate)

class RepoStateUpdater:
    def __init__(self, platform, branch, repo):
        (self.platform, self.branch) = (platform, branch)
        self.git = sh.git.bake(_cwd=repo)
        self.repostate = RepoState(platform, branch, repo)
        self.repohistory = RepoHistory(platform, repo)
    def __update(self, commit, last_good_state, last_bad_state, forward, bisect_state):
        last_build = self.repostate.get_last_build()
        last_good = self.repostate.get_last_good()
        if last_build and last_good:
            if self.git('merge-base', '--is-ancestor', last_build, commit, _ok_code=[0,1]).exit_code == 0:
                rangestate = last_bad_state
                if last_build == last_good:
                    rangestate = last_good_state
                self.repohistory.update_inner_range_state(last_build, commit, CommitState(rangestate), ['GOOD', 'BAD'])
            else:
                first_bad = self.repostate.get_first_bad()
                assert(self.git('merge-base', '--is-ancestor', last_good, commit, _ok_code=[0,1]).exit_code == 0)
                assert(self.git('merge-base', '--is-ancestor', commit, first_bad, _ok_code=[0,1]).exit_code == 0)
                assume_range = (last_good, commit)
                if forward:
                    assume_range = (commit, first_bad)
                self.repohistory.update_inner_range_state(assume_range[0], assume_range[1], CommitState(bisect_state), ['GOOD', 'BAD'])
    def __finalize_bisect(self):
        (first_bad, last_bad) = (self.repostate.get_first_bad(), self.repostate.get_last_bad())
        if not first_bad:
            #assert(self.repostate.get_last_bad() is None)
            return
        last_good = self.repostate.get_last_good()
        if not last_good:
            #assert(self.repostate.get_last_bad() is None)
            return
        if last_good in self.git('rev-list', first_bad, max_count=2).split()[1:]:
            commitstate = self.repohistory.get_commit_state(first_bad)
            commitstate.state = 'BREAKING'
            self.repohistory.set_commit_state(first_bad, commitstate)
        if self.git('merge-base', '--is-ancestor', last_bad, last_good, _ok_code=[0,1]).exit_code == 0:
            self.repostate.clear_first_bad()
            self.repostate.clear_last_bad()
    def set_scheduled(self, commit, builder, estimated_duration):
        # FIXME: dont hardcode limit
        estimated_duration = max(estimated_duration, datetime.timedelta(hours=4))
        commitstate = CommitState('RUNNING', datetime.datetime.now(), builder, estimated_duration)
        self.repohistory.set_commit_state(commit, commitstate)
    def set_finished(self, commit, builder, state, artifactreference):
        if not state in ['GOOD', 'BAD']:
            raise AttributeError
        commitstate = self.repohistory.get_commit_state(commit)
        #assert(commitstate.state == 'RUNNING')
        #assert(commitstate.builder == builder)
        # we want to keep a failure around, even if we have a success somehow
        if not commitstate.state in ['BAD'] or state in ['BAD']:
            commitstate.state = state
            commitstate.finished = datetime.datetime.now()
            commitstate.builder = builder
            commitstate.estimated_duration = None
            commitstate.artifactreference = artifactreference
            self.repohistory.set_commit_state(commit, commitstate)
            if state == 'GOOD':
                last_good = self.repostate.get_last_good()
                if last_good:
                    self.__update(commit, 'ASSUMED_GOOD', 'POSSIBLY_FIXING', False, 'ASSUMED_GOOD')
                if not last_good or self.git('merge-base', '--is-ancestor', last_good, commit, _ok_code=[0,1]).exit_code == 0:
                    self.repostate.set_last_good(commit)
            else:
                self.__update(commit, 'POSSIBLY_BREAKING', 'ASSUMED_BAD', True, 'ASSUMED_BAD')
                (first_bad, last_bad) = (self.repostate.get_first_bad(), self.repostate.get_last_bad())
                if not first_bad or self.git('merge-base', '--is-ancestor', commit, first_bad, _ok_code=[0,1]).exit_code == 0:
                    self.repostate.set_first_bad(commit)
                if not last_bad:
                    self.repostate.set_last_bad(commit)
            self.__finalize_bisect()
# vim: set et sw=4 ts=4:
