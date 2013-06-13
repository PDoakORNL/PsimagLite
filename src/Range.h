// BEGIN LICENSE BLOCK
/*
Copyright (c) 2011, UT-Battelle, LLC
All rights reserved

[PsimagLite, Version 1.0.0]
[by G.A., Oak Ridge National Laboratory]

UT Battelle Open Source Software License 11242008

OPEN SOURCE LICENSE

Subject to the conditions of this License, each
contributor to this software hereby grants, free of
charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), a
perpetual, worldwide, non-exclusive, no-charge,
royalty-free, irrevocable copyright license to use, copy,
modify, merge, publish, distribute, and/or sublicense
copies of the Software.

1. Redistributions of Software must retain the above
copyright and license notices, this list of conditions,
and the following disclaimer.  Changes or modifications
to, or derivative works of, the Software should be noted
with comments and the contributor and organization's
name.

2. Neither the names of UT-Battelle, LLC or the
Department of Energy nor the names of the Software
contributors may be used to endorse or promote products
derived from this software without specific prior written
permission of UT-Battelle.

3. The software and the end-user documentation included
with the redistribution, with or without modification,
must include the following acknowledgment:

"This product includes software produced by UT-Battelle,
LLC under Contract No. DE-AC05-00OR22725  with the
Department of Energy."
 
*********************************************************
DISCLAIMER

THE SOFTWARE IS SUPPLIED BY THE COPYRIGHT HOLDERS AND
CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT OWNER, CONTRIBUTORS, UNITED STATES GOVERNMENT,
OR THE UNITED STATES DEPARTMENT OF ENERGY BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.

NEITHER THE UNITED STATES GOVERNMENT, NOR THE UNITED
STATES DEPARTMENT OF ENERGY, NOR THE COPYRIGHT OWNER, NOR
ANY OF THEIR EMPLOYEES, REPRESENTS THAT THE USE OF ANY
INFORMATION, DATA, APPARATUS, PRODUCT, OR PROCESS
DISCLOSED WOULD NOT INFRINGE PRIVATELY OWNED RIGHTS.

*********************************************************


*/
// END LICENSE BLOCK
/** \ingroup PsimagLite */
/*@{*/

/*! \file Range.h
 *
 * A range class that can be parallelized
 * 
 * Features:
 * 
 * --> Simple interface
 * 
 * --> Load balancing
 * 
 * --> Specialization for serial to avoid performance loss
 * 
 * Future:
 * 
 * --> Support for pthreads and GPUs
 * 
 */
#ifndef RANGE_HEADER_H
#define RANGE_HEADER_H
#include <stdexcept>
#include "Vector.h"

/** How to use the Range class: See drivers/range.cpp
 * 
 */

namespace PsimagLite {

	template<typename ConcurrencyType>
	class Range {

	public:

		typedef typename ConcurrencyType::CommType CommType;
		static const CommType COMM_WORLD;

		Range(SizeType start,
		      SizeType total,
		      const ConcurrencyType& concurrency,
		      const Vector<SizeType>::Type& weights,
		      CommType mpiComm=COMM_WORLD,
		      bool isStrict=false)
		: concurrency_(concurrency),
		  step_(start),
		  total_(total),
		  nprocs_(concurrency.nprocs(mpiComm)),
		  indicesOfThisProc_(nprocs_),
		  isStrict_(isStrict)
		{
			init(weights,mpiComm);
		}

		Range(SizeType start,
		     SizeType total,
		     const ConcurrencyType& concurrency,           
		     CommType mpiComm=COMM_WORLD,
		     bool isStrict=false)
		: concurrency_(concurrency),
		  step_(start),
		  total_(total),
		  nprocs_(concurrency.nprocs(mpiComm)),
		  indicesOfThisProc_(nprocs_),
		  isStrict_(isStrict)
		{
			typename Vector<SizeType>::Type weights(total,1);
			init(weights,mpiComm);
		}

		void next()
		{
			step_++;
		}

		bool end() const
		{
			return (step_>=myIndices_.size() || myIndices_[step_]>=total_ );
		}

// 		bool hasNext() const 
// 		{
// 			return (assigned_ && step_<myIndices_.size() && myIndices_[step_]<total_ );
// 		}

		SizeType index() const { return myIndices_[step_]; }

	private:

		const ConcurrencyType& concurrency_;
		SizeType step_; // step within this processor
		SizeType total_; // total number of indices total_(total),
		SizeType nprocs_;
		Vector<Vector<SizeType>::Type >::Type indicesOfThisProc_; // given rank and step it maps the index
		bool isStrict_; // does nproc need to divide total?
		typename Vector<SizeType>::Type myIndices_; // indices assigned to this processor

		void init(const typename Vector<SizeType>::Type& weights,CommType mpiComm)
		{ 
			if (isStrict_ && total_%nprocs_!=0)
				throw RuntimeError("Nprocs must divide total for this range\n");

			// distribute the load among the processors
			typename Vector<SizeType>::Type loads(nprocs_,0);
			
			for (SizeType i=0;i<total_;i++) {
				SizeType r = findLowestLoad(loads);
				indicesOfThisProc_[r].push_back(i);
				loads[r] += weights[i];
			}
			// set myIndices_
			SizeType r1=concurrency_.rank(mpiComm);
			myIndices_=indicesOfThisProc_[r1];
		}

		SizeType findLowestLoad(const Vector<SizeType>::Type& loads) const
		{
			SizeType x= 1000000;
			SizeType ret=0;
			for (SizeType i=0;i<loads.size();i++) {
				if (loads[i]<x) {
					x=loads[i];
					ret =i;
				}
			}
			return ret;
		}
	}; // class Range

	template<typename ConcurrencyType>
	const typename Range<ConcurrencyType>::CommType 
	Range<ConcurrencyType>::COMM_WORLD = ConcurrencyType::COMM_WORLD;


	//! Specialization for performance reasons
	template<>
	class Range<ConcurrencySerial<> > {

		typedef ConcurrencySerial<> ConcurrencyType;

	public:

		typedef ConcurrencyType::CommType CommType;

		Range(SizeType start,
		     SizeType total,
		     ConcurrencyType& concurrency,
		     const Vector<SizeType>::Type& weights,
		     CommType mpiComm=0) : step_(start),total_(total)
		{}

		Range(SizeType start,
		     SizeType total,
		     ConcurrencyType& concurrency,           
		     CommType mpiComm=0) : step_(start),total_(total)
		{}

		void next()
		{
			step_++;
		}

		bool end() const { return step_>=total_; }

// 		bool hasNext() const { return step_ <total_; }

		SizeType index() const { return step_; }

	private:

		SizeType step_; // step within this processor
		SizeType total_; // total number of indices
	}; // class Range
} // namespace PsimagLite

/*@}*/	
#endif // RANGE_HEADER_H
